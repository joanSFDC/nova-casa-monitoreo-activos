import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import LOCALE from "@salesforce/i18n/locale";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import obtenerPanel from "@salesforce/apex/MonitorControlador.obtenerPanel";
import abrirIntervencion from "@salesforce/apex/MonitorControlador.abrirIntervencion";
import NotaIntervencion from "c/notaIntervencion";

const CANAL_TIMBRE = "/event/Panel_Actualizado__e";
const ESPERA_MS = 2000;
const VIGILANCIA_MS = 60000;
const POR_BOTON = "boton";
const POR_TIMBRE = "timbre";
const POR_VIGILANCIA = "vigilancia";
const AVISO_SIN_TIEMPO_REAL =
  "La actualización automática no está disponible. El monitor se revisa solo cada minuto y con Actualizar.";
const SIN_COMUNICACION = "SinComunicacion";
const SIN_VALOR = "—";

const FICHAS = [
  {
    valor: "Critico",
    campo: "criticos",
    singular: "crítico",
    plural: "críticos",
    clase: "critico"
  },
  {
    valor: "Advertencia",
    campo: "advertencias",
    singular: "advertencia",
    plural: "advertencias",
    clase: "advertencia"
  },
  {
    valor: "Normal",
    campo: "normales",
    singular: "normal",
    plural: "normales",
    clase: "normal"
  },
  {
    valor: SIN_COMUNICACION,
    campo: "sinComunicacion",
    singular: "sin comunicación",
    plural: "sin comunicación",
    clase: "perdida"
  }
];

const ORDENES = [
  { label: "Severidad, lo grave primero", value: "severidad" },
  { label: "Antigüedad, lo más viejo primero", value: "antiguedad" },
  { label: "Equipo, de la A a la Z", value: "equipo" },
  { label: "Edificio, de la A a la Z", value: "edificio" }
];

const COMUNICACION = {
  LOST: "perdida",
  RESTORED: "recuperada",
  HEALTHY: "enlinea"
};

function normalizar(texto) {
  return (texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function tiempo(fecha) {
  const valor = fecha ? Date.parse(fecha) : NaN;
  return Number.isNaN(valor) ? Number.MAX_SAFE_INTEGER : valor;
}

export default class MonitorDeActivos extends NavigationMixin(
  LightningElement
) {
  edificioId = "";
  filtroSeveridad = null;
  filtroTipo = "";
  orden = "severidad";
  busqueda = "";
  error;
  errorEsPermiso = false;
  actualizando = false;
  anuncio = "";
  anunciarCarga = true;
  tiempoRealCaido = false;
  suscripcion;
  temporizador;
  vigilancia;
  _wire;

  @wire(obtenerPanel, { edificioId: "$edificioId" })
  recibirPanel(resultado) {
    this._wire = resultado;
    if (resultado.data) {
      this.error = undefined;
      this.errorEsPermiso = false;
      if (this.anunciarCarga) {
        this.anunciarCarga = false;
        this.anuncio = this.textoActualizado();
      }
    } else if (resultado.error) {
      this.error = this.textoError(resultado.error);
      this.errorEsPermiso = this.esPermiso(resultado.error);
      this.anuncio = "No se pudo cargar el monitor. " + this.error;
    }
  }

  connectedCallback() {
    this.anuncio = "Cargando el monitor";
    onError(() => {
      this.avisarSinTiempoReal();
    });
    this.suscribir();
    this.vigilar();
    this.alCambiarVisibilidad = () => this.cambiarVisibilidad();
    document.addEventListener("visibilitychange", this.alCambiarVisibilidad);
  }

  suscribir() {
    subscribe(CANAL_TIMBRE, -1, () => {
      this.tiempoRealCaido = false;
      this.programarConsulta();
    })
      .then((respuesta) => {
        if (this.pausado) {
          unsubscribe(respuesta);
          return;
        }
        this.suscripcion = respuesta;
      })
      .catch(() => {
        this.avisarSinTiempoReal();
      });
  }

  /**
   * Cada monitor abierto recibe cada timbre, y las entregas del día son un límite
   * de la org: con la pestaña oculta no escucha ni consulta. Al volver se pone al
   * día solo.
   */
  cambiarVisibilidad() {
    if (document.visibilityState === "hidden") {
      this.pausar();
      return;
    }
    if (!this.pausado) {
      return;
    }
    this.pausado = false;
    this.suscribir();
    this.consultar(POR_VIGILANCIA);
  }

  pausar() {
    this.pausado = true;
    this.detener();
  }

  detener() {
    if (this.temporizador) {
      clearTimeout(this.temporizador);
      this.temporizador = undefined;
    }
    if (this.vigilancia) {
      clearTimeout(this.vigilancia);
      this.vigilancia = undefined;
    }
    if (this.suscripcion) {
      unsubscribe(this.suscripcion);
      this.suscripcion = undefined;
    }
  }

  avisarSinTiempoReal() {
    if (this.tiempoRealCaido) {
      return;
    }
    this.tiempoRealCaido = true;
    this.anuncio = AVISO_SIN_TIEMPO_REAL;
  }

  disconnectedCallback() {
    document.removeEventListener("visibilitychange", this.alCambiarVisibilidad);
    this.detener();
  }

  get panel() {
    return this._wire && this._wire.data ? this._wire.data : null;
  }

  get cargando() {
    return !this.panel && !this.error;
  }

  get filas() {
    return this.panel && this.panel.filas ? this.panel.filas : [];
  }

  /**
   * Severidad, tipo y búsqueda filtran en el navegador sobre filas que el
   * servidor ya autorizó: no aparece nada que el usuario no pueda ver.
   */
  get filasFiltradas() {
    const texto = normalizar(this.busqueda);
    return this.filas.filter((fila) => {
      if (this.filtroSeveridad === SIN_COMUNICACION) {
        if (fila.comunicacionEstado !== "LOST") {
          return false;
        }
      } else if (
        this.filtroSeveridad &&
        fila.severidad !== this.filtroSeveridad
      ) {
        return false;
      }
      if (this.filtroTipo && fila.tipoActivo !== this.filtroTipo) {
        return false;
      }
      if (texto) {
        const donde = normalizar(
          [fila.equipo, fila.codigo, fila.medicion].join(" ")
        );
        if (!donde.includes(texto)) {
          return false;
        }
      }
      return true;
    });
  }

  ordenar(filas) {
    const conIndice = filas.map((fila, indice) => ({ fila, indice }));
    const criterio = {
      severidad: (a, b) =>
        (b.fila.severidadNivel || 0) - (a.fila.severidadNivel || 0),
      antiguedad: (a, b) =>
        tiempo(a.fila.fechaOrigen) - tiempo(b.fila.fechaOrigen),
      equipo: (a, b) =>
        (a.fila.equipo || "").localeCompare(b.fila.equipo || "", "es"),
      edificio: (a, b) =>
        (b.fila.severidadNivel || 0) - (a.fila.severidadNivel || 0)
    }[this.orden];
    conIndice.sort((a, b) => criterio(a, b) || a.indice - b.indice);
    return conIndice.map((item) => item.fila);
  }

  /**
   * Una sección por edificio, con su ciudad y su resumen. Con el orden por
   * severidad, el edificio con lo más grave va primero.
   */
  get grupos() {
    const porEdificio = new Map();
    for (const fila of this.ordenar(this.filasFiltradas)) {
      const id = fila.edificioId || fila.edificio;
      if (!porEdificio.has(id)) {
        porEdificio.set(id, {
          id,
          nombre: fila.edificio,
          ciudad: fila.ciudad,
          peor: 0,
          filas: []
        });
      }
      const grupo = porEdificio.get(id);
      grupo.peor = Math.max(grupo.peor, fila.severidadNivel || 0);
      grupo.filas.push(this.decorar(fila));
    }
    const grupos = Array.from(porEdificio.values());
    grupos.sort((a, b) => {
      if (this.orden === "severidad" && b.peor !== a.peor) {
        return b.peor - a.peor;
      }
      return (a.nombre || "").localeCompare(b.nombre || "", "es");
    });
    return grupos.map((grupo) => ({
      ...grupo,
      resumen: this.resumen(grupo.filas)
    }));
  }

  resumen(filas) {
    const criticos = filas.filter((f) => f.severidad === "Critico").length;
    const advertencias = filas.filter(
      (f) => f.severidad === "Advertencia"
    ).length;
    const cortes = filas.filter((f) => f.comunicacionEstado === "LOST").length;
    const partes = [];
    if (criticos) {
      partes.push(criticos + (criticos === 1 ? " crítico" : " críticos"));
    }
    if (advertencias) {
      partes.push(
        advertencias + (advertencias === 1 ? " advertencia" : " advertencias")
      );
    }
    if (cortes) {
      partes.push(cortes + " sin comunicación");
    }
    return partes.length ? partes.join(" · ") : "Todo normal";
  }

  decorar(fila) {
    const severidad = {
      Critico: "critico",
      Advertencia: "advertencia"
    }[fila.severidad];
    return {
      ...fila,
      claseFila: "fila-equipo fila_" + (severidad || "normal"),
      claseComunicacion:
        "comunicacion comunicacion_" +
        (COMUNICACION[fila.comunicacionEstado] || "desconocida"),
      textoLectura: fila.lectura || fila.valor || SIN_VALOR,
      detalleEquipo: [fila.tipoActivoEtiqueta, fila.codigo]
        .filter(Boolean)
        .join(" · "),
      etiquetaAccion: fila.casoId ? "Ver incidente" : "Abrir intervención",
      tituloAccion: fila.casoId
        ? "Abrir el incidente existente"
        : "Abrir una intervención para este equipo"
    };
  }

  get sinResultadosDeFiltro() {
    return this.filas.length > 0 && this.filasFiltradas.length === 0;
  }

  get fichas() {
    return FICHAS.map((ficha) => {
      const numero = this.panel ? this.panel[ficha.campo] || 0 : 0;
      const pulsada = this.filtroSeveridad === ficha.valor;
      const clases = ["ficha"];
      clases.push(numero > 0 ? "ficha_" + ficha.clase : "ficha_vacia");
      if (pulsada) {
        clases.push("ficha_pulsada");
      }
      return {
        valor: ficha.valor,
        etiqueta: numero + " " + (numero === 1 ? ficha.singular : ficha.plural),
        clase: clases.join(" "),
        pulsada: pulsada ? "true" : "false"
      };
    });
  }

  get opcionesEdificio() {
    const opciones = [{ label: "Todos los edificios", value: "" }];
    if (!this.panel || !this.panel.edificios) {
      return opciones;
    }
    return opciones.concat(
      this.panel.edificios.map((edificio) => ({
        label: edificio.nombre,
        value: edificio.id
      }))
    );
  }

  get mostrarSelectorEdificio() {
    return (
      this.panel && this.panel.edificios && this.panel.edificios.length > 1
    );
  }

  get opcionesTipo() {
    const tipos = new Map();
    for (const fila of this.filas) {
      if (fila.tipoActivo && !tipos.has(fila.tipoActivo)) {
        tipos.set(fila.tipoActivo, fila.tipoActivoEtiqueta || fila.tipoActivo);
      }
    }
    const opciones = Array.from(tipos, ([value, label]) => ({ label, value }));
    opciones.sort((a, b) => a.label.localeCompare(b.label, "es"));
    return [{ label: "Todos los tipos", value: "" }].concat(opciones);
  }

  get opcionesOrden() {
    return ORDENES;
  }

  get hayFiltros() {
    return Boolean(this.filtroSeveridad || this.filtroTipo || this.busqueda);
  }

  textoError(error) {
    if (!error) {
      return "No se pudo cargar el monitor.";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((item) => item.message).join(" ");
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || "No se pudo cargar el monitor.";
  }

  esPermiso(error) {
    const texto = this.textoError(error).toLowerCase();
    return (
      texto.includes("insufficient") ||
      texto.includes("permission") ||
      texto.includes("no such column") ||
      texto.includes("acceso")
    );
  }

  programarConsulta() {
    if (this.temporizador) {
      clearTimeout(this.temporizador);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- una sola consulta por rafaga de timbres
    this.temporizador = setTimeout(() => {
      this.temporizador = undefined;
      this.consultar(POR_TIMBRE);
    }, ESPERA_MS);
  }

  /**
   * Sin timbres no hay consultas, y el aviso de atraso y las antiguedades solo
   * los recalcula el servidor. Si pasa un minuto sin consultar, se consulta.
   */
  vigilar() {
    if (this.vigilancia) {
      clearTimeout(this.vigilancia);
    }
    if (this.pausado) {
      this.vigilancia = undefined;
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- la ingesta parada no manda timbres
    this.vigilancia = setTimeout(() => {
      this.vigilancia = undefined;
      this.consultar(POR_VIGILANCIA);
    }, VIGILANCIA_MS);
  }

  consultar(origen) {
    if (!this._wire) {
      this.vigilar();
      return Promise.resolve();
    }
    const enSilencio = origen === POR_VIGILANCIA;
    const atrasadaAntes = this.consultaAtrasada;
    if (!enSilencio) {
      this.actualizando = true;
    }
    if (origen === POR_BOTON) {
      this.anuncio = "Actualizando el monitor";
    }
    return refreshApex(this._wire)
      .then(() => {
        this.error = undefined;
        this.errorEsPermiso = false;
        if (!enSilencio) {
          this.anuncio = this.textoActualizado();
        } else if (this.consultaAtrasada !== atrasadaAntes) {
          this.anuncio = this.consultaAtrasada
            ? "La última consulta al proveedor se atrasó. Los datos pueden no estar al día."
            : "La consulta al proveedor volvió a estar al día.";
        }
      })
      .catch((error) => {
        this.error = this.textoError(error);
        this.errorEsPermiso = this.esPermiso(error);
        this.anuncio = "No se pudo actualizar el monitor. " + this.error;
      })
      .finally(() => {
        this.actualizando = false;
        this.vigilar();
      });
  }

  get consultaAtrasada() {
    return Boolean(this.panel && this.panel.consultaAtrasada);
  }

  textoActualizado() {
    const hora = new Intl.DateTimeFormat(LOCALE, {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: TIME_ZONE
    }).format(new Date());
    return "Monitor actualizado a las " + hora;
  }

  handleEdificio(event) {
    this.edificioId = event.detail.value;
    this.filtroSeveridad = null;
    this.anunciarCarga = true;
    this.anuncio = "Actualizando el monitor";
  }

  handleFiltro(event) {
    const valor = event.currentTarget.dataset.severidad;
    this.filtroSeveridad = this.filtroSeveridad === valor ? null : valor;
  }

  handleTipo(event) {
    this.filtroTipo = event.detail.value;
  }

  handleOrden(event) {
    this.orden = event.detail.value;
  }

  handleBusqueda(event) {
    this.busqueda = event.detail.value || "";
  }

  handleQuitarFiltros() {
    this.filtroSeveridad = null;
    this.filtroTipo = "";
    this.busqueda = "";
  }

  handleActualizar() {
    this.consultar(POR_BOTON);
  }

  handleReintentar() {
    this.error = undefined;
    this.consultar(POR_BOTON);
  }

  handleActivo(event) {
    const id = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName: "Activo__c",
        actionName: "view"
      }
    });
  }

  handleAccion(event) {
    const estadoId = event.currentTarget.dataset.estado;
    const casoId = event.currentTarget.dataset.caso;
    if (casoId) {
      this.irAlCaso(casoId);
      return;
    }
    const fila = this.filas.find((item) => item.estadoId === estadoId);
    NotaIntervencion.open({
      size: "small",
      equipo: fila ? fila.equipo + " · " + fila.medicion : ""
    }).then((respuesta) => {
      if (respuesta) {
        this.abrir(estadoId, respuesta.nota);
      }
    });
  }

  abrir(estadoId, nota) {
    this.actualizando = true;
    abrirIntervencion({ estadoId, nota })
      .then((id) => {
        this.irAlCaso(id);
      })
      .catch((error) => {
        this.error = this.textoError(error);
        this.errorEsPermiso = this.esPermiso(error);
      })
      .finally(() => {
        this.actualizando = false;
      });
  }

  irAlCaso(id) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName: "Case",
        actionName: "view"
      }
    });
  }
}
