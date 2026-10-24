#!/usr/bin/env python3
"""Orquesta la prueba de carga (docs/12-plan-de-pruebas.md, «La prueba de carga»).

Uso, desde la raiz del repositorio:

    python3 load-test/carga.py desplegar          # sube el generador a la org
    python3 load-test/carga.py preparar           # edificio de carga y sus 5 equipos
    python3 load-test/carga.py lanzar META [RITMO] # sigue hasta META filas, RITMO por hora
    python3 load-test/carga.py estado             # avance, pendientes, trabajos y limites
    python3 load-test/carga.py medir ETIQUETA     # foto del escalon en resultados/
    python3 load-test/carga.py detener            # aborta el ciclo programado
    python3 load-test/carga.py limpiar            # borra todo lo que creo la carga
    python3 load-test/carga.py retirar            # quita el generador de la org

La org sale de NC_ORG o, si no esta, del alias novacasa2. No imprime credenciales.
"""
import datetime
import json
import os
import statistics
import subprocess
import sys
import tempfile

ORG = os.environ.get("NC_ORG", "novacasa2")
AQUI = os.path.dirname(os.path.abspath(__file__))
RESULTADOS = os.path.join(AQUI, "resultados")
ESCALONES = os.path.join(RESULTADOS, "escalones.json")
PREFIJO = "nova-casa-simulator|2026-10-24T21:00:00Z|carga_"
TRABAJO = "Nova Casa - Carga sintetica"
RITMO = 200000
LIMITES = (
    "HourlyPublishedPlatformEvents",
    "DailyAsyncApexExecutions",
    "DailyWorkflowEmails",
    "DataStorageMB",
    "DailyApiRequests",
)


def sf(*args):
    r = subprocess.run(
        ["sf", *args, "-o", ORG, "--json"], capture_output=True, text=True
    )
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        raise SystemExit("sf no devolvio JSON: " + r.stderr[-400:])


def consulta(soql):
    d = sf("data", "query", "-q", soql)
    if d.get("status") != 0:
        raise SystemExit("Consulta fallida: " + str(d.get("message"))[:400])
    return d["result"]


def filas_de(soql):
    return [
        {k: v for k, v in r.items() if k != "attributes"}
        for r in consulta(soql)["records"]
    ]


def apex(codigo):
    with tempfile.NamedTemporaryFile("w", suffix=".apex", delete=False) as f:
        f.write(codigo)
    try:
        d = sf("apex", "run", "-f", f.name)
    finally:
        os.unlink(f.name)
    res = d.get("result") or {}
    if not res.get("success"):
        raise SystemExit(
            "Apex fallido: "
            + str(
                res.get("compileProblem")
                or res.get("exceptionMessage")
                or d.get("message")
            )[:400]
        )


def limites():
    d = sf("org", "list", "limits")
    return {
        x["name"]: {"max": x["max"], "restante": x["remaining"]}
        for x in d.get("result") or []
        if x["name"] in LIMITES
    }


def avance():
    """Filas de la carga y el indice del proximo mensaje."""
    ultima = filas_de(
        f"SELECT Clave__c FROM Senal__c WHERE Clave__c LIKE '{PREFIJO}%' "
        "ORDER BY Clave__c DESC LIMIT 1"
    )
    siguiente = int(ultima[0]["Clave__c"].rsplit("_", 1)[1]) + 1 if ultima else 0
    filas = consulta(
        f"SELECT COUNT() FROM Senal__c WHERE Clave__c LIKE '{PREFIJO}%'"
    )["totalSize"]
    return filas, siguiente


def ahora():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(momento):
    return momento.strftime("%Y-%m-%dT%H:%M:%SZ")


def leer_escalones():
    if not os.path.exists(ESCALONES):
        return []
    with open(ESCALONES, encoding="utf-8") as f:
        return json.load(f)


def guardar(ruta, datos):
    os.makedirs(RESULTADOS, exist_ok=True)
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)


def desplegar():
    d = sf("project", "deploy", "start", "-d", os.path.join(AQUI, "main"))
    print("despliegue", d.get("status"), (d.get("result") or {}).get("status"))


def preparar():
    apex("CargaSinteticaBatch.preparar();")
    equipos = filas_de(
        "SELECT Codigo_Externo__c, Edificio__r.Ciudad__c FROM Activo__c "
        "WHERE Codigo_Externo__c LIKE 'AST-CARGA-%' ORDER BY Codigo_Externo__c"
    )
    for e in equipos:
        print(e["Codigo_Externo__c"], e["Edificio__r"]["Ciudad__c"])


def lanzar(meta, ritmo):
    filas, siguiente = avance()
    if filas >= meta:
        raise SystemExit(f"Ya hay {filas} filas, la meta {meta} esta cumplida")
    apex(f"CargaSinteticaBatch.lanzar({siguiente}L, {filas}L, {meta}L, {ritmo});")
    escalones = leer_escalones()
    escalones.append(
        {
            "meta": meta,
            "ritmo": ritmo,
            "inicio": iso(ahora()),
            "filas_al_iniciar": filas,
            "siguiente_al_iniciar": siguiente,
            "limites_al_iniciar": limites(),
        }
    )
    guardar(ESCALONES, escalones)
    print(f"lanzado: desde el mensaje {siguiente}, {filas} filas, meta {meta}, {ritmo}/h")


def estado():
    filas, siguiente = avance()
    pendientes = consulta(
        "SELECT COUNT() FROM Senal__c WHERE Resultado_Indice__c = 'Pendiente' "
        f"AND Clave__c LIKE '{PREFIJO}%'"
    )["totalSize"]
    print(f"filas {filas}  proximo mensaje {siguiente}  pendientes {pendientes}")
    for t in filas_de(
        "SELECT CronJobDetail.Name, NextFireTime FROM CronTrigger "
        f"WHERE CronJobDetail.Name LIKE '{TRABAJO}%'"
    ):
        print("programado", t["CronJobDetail"]["Name"], t["NextFireTime"])
    for j in filas_de(
        "SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, "
        "ExtendedStatus FROM AsyncApexJob WHERE ApexClass.Name = "
        "'CargaSinteticaBatch' AND JobType = 'BatchApex' "
        "ORDER BY CreatedDate DESC LIMIT 2"
    ):
        print(
            "ciclo",
            j["Status"],
            f"{j['JobItemsProcessed']}/{j['TotalJobItems']}",
            "errores",
            j["NumberOfErrors"],
            (j.get("ExtendedStatus") or "")[:120],
        )
    for nombre, v in limites().items():
        print(f"{nombre:32} restante {v['restante']:>9} de {v['max']}")


def percentil(valores, p):
    if not valores:
        return None
    orden = sorted(valores)
    return orden[min(len(orden) - 1, int(round(p / 100 * (len(orden) - 1))))]


def segundos(a, b):
    fmt = "%Y-%m-%dT%H:%M:%S.%f%z"
    return (
        datetime.datetime.strptime(b, fmt) - datetime.datetime.strptime(a, fmt)
    ).total_seconds()


def medir(etiqueta):
    escalones = leer_escalones()
    escalon = escalones[-1] if escalones else {}
    filas, siguiente = avance()
    momento = ahora()

    por_resultado = {}
    for resultado in (
        "Pendiente",
        "Aplicado",
        "Atrasado",
        "Rechazado",
        "Conflicto",
        "Fallido",
    ):
        por_resultado[resultado] = consulta(
            f"SELECT COUNT() FROM Senal__c WHERE Clave__c LIKE '{PREFIJO}%' "
            f"AND Resultado_Indice__c = '{resultado}'"
        )["totalSize"]

    muestra = filas_de(
        "SELECT CreatedDate, Fecha_Procesamiento__c FROM Senal__c "
        f"WHERE Clave__c LIKE '{PREFIJO}%' "
        "AND Resultado_Indice__c IN ('Aplicado', 'Atrasado') "
        "ORDER BY Clave__c DESC LIMIT 2000"
    )
    latencias = [
        segundos(m["CreatedDate"], m["Fecha_Procesamiento__c"])
        for m in muestra
        if m.get("Fecha_Procesamiento__c")
    ]
    fallidas = filas_de(
        "SELECT Detalle__c FROM Senal__c WHERE Resultado_Indice__c = 'Fallido' "
        f"AND Clave__c LIKE '{PREFIJO}%' ORDER BY Clave__c DESC LIMIT 5"
    )
    desde = escalon.get("inicio") or iso(momento - datetime.timedelta(hours=1))
    trabajos = filas_de(
        "SELECT ApexClass.Name, Status, COUNT(Id) n, SUM(NumberOfErrors) e "
        f"FROM AsyncApexJob WHERE CreatedDate >= {desde} "
        "AND ApexClass.Name IN ('CargaSinteticaBatch', 'IngestaQueueable', "
        "'IngestaSchedulable', 'BitacoraRetencionBatch') "
        "GROUP BY ApexClass.Name, Status"
    )
    errores_ciclo = filas_de(
        "SELECT ExtendedStatus FROM AsyncApexJob WHERE ApexClass.Name = "
        f"'CargaSinteticaBatch' AND CreatedDate >= {desde} "
        "AND NumberOfErrors > 0 ORDER BY CreatedDate DESC LIMIT 3"
    )
    suscriptor = filas_de(
        "SELECT Position, Status, Retries, LastError FROM EventBusSubscriber "
        "WHERE Topic = 'Aviso_de_Senal__e' AND Type = 'ApexTrigger'"
    )
    control = filas_de(
        "SELECT Ultima_Consulta_Exitosa__c, Caida_Desde__c, Motivo_Caida__c, "
        "Fallos_Consecutivos__c, Ultimo_Error__c FROM Control_de_Ingesta__c "
        "WHERE Activo__c = true LIMIT 1"
    )
    reales_pendientes = consulta(
        "SELECT COUNT() FROM Senal__c WHERE Resultado_Indice__c = 'Pendiente' "
        f"AND CreatedDate >= {iso(momento - datetime.timedelta(minutes=15))} "
        f"AND (NOT Clave__c LIKE '{PREFIJO}%')"
    )["totalSize"]
    incidentes = consulta(
        "SELECT COUNT() FROM Case WHERE Ciudad__c = 'Carga'"
    )["totalSize"]

    transcurrido = None
    ritmo_real = None
    if escalon.get("inicio"):
        transcurrido = (
            momento
            - datetime.datetime.strptime(escalon["inicio"], "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=datetime.timezone.utc
            )
        ).total_seconds()
        if transcurrido > 0:
            ritmo_real = round(
                (filas - escalon["filas_al_iniciar"]) * 3600 / transcurrido
            )

    foto = {
        "etiqueta": etiqueta,
        "momento": iso(momento),
        "escalon": {k: v for k, v in escalon.items() if k != "limites_al_iniciar"},
        "filas": filas,
        "proximo_mensaje": siguiente,
        "por_resultado": por_resultado,
        "segundos_desde_el_inicio": transcurrido,
        "filas_por_hora": ritmo_real,
        "latencia_procesamiento_s": {
            "muestra": len(latencias),
            "p50": percentil(latencias, 50),
            "p95": percentil(latencias, 95),
            "max": max(latencias) if latencias else None,
            "media": round(statistics.mean(latencias), 2) if latencias else None,
        },
        "fallidas_muestra": [f.get("Detalle__c") for f in fallidas],
        "trabajos": trabajos,
        "errores_del_generador": [e.get("ExtendedStatus") for e in errores_ciclo],
        "suscriptor_aviso": suscriptor,
        "ingesta_en_vivo": {
            "control": control[0] if control else None,
            "pendientes_reales_15_min": reales_pendientes,
        },
        "incidentes_de_carga": incidentes,
        "limites": limites(),
        "limites_al_iniciar": escalon.get("limites_al_iniciar"),
    }
    guardar(os.path.join(RESULTADOS, f"{etiqueta}.json"), foto)
    print(json.dumps(foto, ensure_ascii=False, indent=2))


def detener():
    apex("CargaSinteticaBatch.detener();")
    print("detenido")


def limpiar():
    apex("CargaSinteticaLimpiezaBatch.lanzar();")
    print("limpieza lanzada: sigue su avance con estado")


def retirar():
    d = sf(
        "project",
        "deploy",
        "start",
        "--manifest",
        os.path.join(AQUI, "retiro", "package.xml"),
        "--post-destructive-changes",
        os.path.join(AQUI, "retiro", "destructiveChanges.xml"),
    )
    print("retiro", d.get("status"), (d.get("result") or {}).get("status"))


def main(argv):
    if not argv:
        raise SystemExit(__doc__)
    orden, resto = argv[0], argv[1:]
    if orden == "desplegar":
        desplegar()
    elif orden == "preparar":
        preparar()
    elif orden == "lanzar":
        lanzar(int(resto[0]), int(resto[1]) if len(resto) > 1 else RITMO)
    elif orden == "estado":
        estado()
    elif orden == "medir":
        medir(resto[0])
    elif orden == "detener":
        detener()
    elif orden == "limpiar":
        limpiar()
    elif orden == "retirar":
        retirar()
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
