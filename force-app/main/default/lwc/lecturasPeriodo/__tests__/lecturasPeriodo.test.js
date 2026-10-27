import { createElement } from "lwc";
import LecturasPeriodo from "c/lecturasPeriodo";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import pagina from "@salesforce/apex/LecturasPeriodoControlador.pagina";

jest.mock(
  "@salesforce/apex/LecturasPeriodoControlador.pagina",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function filas(desde, cuantas) {
  return Array.from({ length: cuantas }, (_, i) => ({
    id: "a07xx" + String(desde + i).padStart(10, "0"),
    nombre: "SEN-" + (2259900 - desde - i),
    recibida: "2026-10-22T20:41:00.000Z",
    lectura: "4,93 bar",
    resultado: i % 2 ? "Atrasado" : "Aplicado",
    resultadoEtiqueta: i % 2 ? "Atrasado" : "Aplicado"
  }));
}

const PRIMERA = {
  filas: filas(0, 50),
  hayMas: true,
  siguienteHasta: "2026-10-22T20:41:00.000Z",
  siguienteVistos: ["a07xx0000000049"],
  equipo: "Bomba de presión de agua",
  cerrado: false,
  fueraDeVentana: true
};

const SEGUNDA = {
  filas: [
    ...filas(50, 2),
    {
      id: "a07xx0000000052",
      nombre: "SEN-2259848",
      recibida: "2026-10-22T20:35:00.000Z",
      lectura: "72,5 PSI",
      resultado: "Rechazado",
      resultadoEtiqueta: "Rechazado",
      motivo: "Unidad no compatible"
    }
  ],
  hayMas: false,
  siguienteHasta: "2026-10-22T20:30:00.000Z",
  siguienteVistos: [],
  equipo: "Bomba de presión de agua",
  cerrado: false,
  fueraDeVentana: true
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

async function crear(conAcceso = true) {
  const elemento = createElement("c-lecturas-periodo", { is: LecturasPeriodo });
  elemento.recordId = "500xx0000001";
  document.body.appendChild(elemento);
  if (conAcceso) {
    getObjectInfo.emit({ apiName: "Senal__c" });
  } else {
    getObjectInfo.error();
  }
  await flushPromises();
  return elemento;
}

function boton(elemento, clase) {
  return elemento.shadowRoot.querySelector("button." + clase);
}

describe("c-lecturas-periodo", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("no aparece para quien no lee la bitácora", async () => {
    const elemento = await crear(false);
    expect(elemento.shadowRoot.querySelector("article")).toBeNull();
    expect(pagina).not.toHaveBeenCalled();
  });

  it("entra cerrada y no consulta nada", async () => {
    const elemento = await crear();
    const alternar = boton(elemento, "alternar");
    expect(alternar.textContent.trim()).toBe("Ver lecturas");
    expect(alternar.getAttribute("aria-expanded")).toBe("false");
    expect(elemento.shadowRoot.querySelector("table")).toBeNull();
    expect(pagina).not.toHaveBeenCalled();
  });

  it("al abrir trae la primera página con su rango y la nota de la ventana", async () => {
    pagina.mockResolvedValueOnce(PRIMERA);
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    expect(pagina).toHaveBeenCalledWith({
      casoId: "500xx0000001",
      hasta: null,
      vistos: []
    });
    const raiz = elemento.shadowRoot;
    expect(raiz.querySelectorAll("tbody tr")).toHaveLength(50);
    expect(raiz.querySelector(".rango").textContent).toBe("Lecturas 1 a 50");
    expect(raiz.querySelector("tbody .lectura").textContent).toBe("4,93 bar");
    expect(raiz.querySelector("tbody .resultado").classList).toContain(
      "resultado_aplicado"
    );
    expect(raiz.querySelector(".nota").textContent).toContain(
      "«Señales del caso»"
    );
    expect(boton(elemento, "alternar").getAttribute("aria-expanded")).toBe(
      "true"
    );
    expect(boton(elemento, "anterior").disabled).toBe(true);
    expect(boton(elemento, "siguiente").disabled).toBe(false);
  });

  it("pide la siguiente con la posición y vuelve sin pedir otra vez", async () => {
    pagina.mockResolvedValueOnce(PRIMERA).mockResolvedValueOnce(SEGUNDA);
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    boton(elemento, "siguiente").click();
    await flushPromises();
    expect(pagina).toHaveBeenLastCalledWith({
      casoId: "500xx0000001",
      hasta: PRIMERA.siguienteHasta,
      vistos: PRIMERA.siguienteVistos
    });
    expect(elemento.shadowRoot.querySelector(".rango").textContent).toBe(
      "Lecturas 51 a 53"
    );
    const rechazada = elemento.shadowRoot.querySelectorAll("tbody tr")[2];
    expect(rechazada.querySelector(".lectura").textContent).toBe("72,5 PSI");
    expect(rechazada.querySelector(".resultado").classList).toContain(
      "resultado_rechazado"
    );
    expect(rechazada.querySelector(".motivo").textContent).toBe(
      "Unidad no compatible"
    );
    expect(
      elemento.shadowRoot
        .querySelectorAll("tbody tr")[0]
        .querySelector(".motivo")
    ).toBeNull();
    expect(boton(elemento, "siguiente").disabled).toBe(true);

    boton(elemento, "anterior").click();
    await flushPromises();
    expect(elemento.shadowRoot.querySelector(".rango").textContent).toBe(
      "Lecturas 1 a 50"
    );
    boton(elemento, "siguiente").click();
    await flushPromises();
    boton(elemento, "primera").click();
    await flushPromises();
    expect(elemento.shadowRoot.querySelector(".rango").textContent).toBe(
      "Lecturas 1 a 50"
    );
    expect(pagina).toHaveBeenCalledTimes(2);
  });

  it("dice cuando no hay lecturas en el periodo", async () => {
    pagina.mockResolvedValueOnce({
      filas: [],
      hayMas: false,
      siguienteVistos: [],
      fueraDeVentana: false
    });
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    expect(elemento.shadowRoot.querySelector(".vacio").textContent.trim()).toBe(
      "No hay lecturas de este equipo en el periodo del incidente."
    );
    expect(elemento.shadowRoot.querySelector(".nota")).toBeNull();
  });

  it("se oculta si el servidor no deja ver el caso", async () => {
    pagina.mockResolvedValueOnce(null);
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    expect(elemento.shadowRoot.querySelector("article")).toBeNull();
  });

  it("muestra el error cuando no carga", async () => {
    pagina.mockRejectedValueOnce(new Error("falla"));
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    expect(
      elemento.shadowRoot.querySelector('[role="alert"]').textContent
    ).toBe("No se pudieron cargar las lecturas del periodo.");
  });

  it("es una tabla con encabezados y la tarjeta tiene nombre", async () => {
    pagina.mockResolvedValueOnce(SEGUNDA);
    const elemento = await crear();
    boton(elemento, "alternar").click();
    await flushPromises();

    const raiz = elemento.shadowRoot;
    expect(raiz.querySelector("caption").textContent).toContain(
      "Lecturas del equipo"
    );
    expect(
      Array.from(raiz.querySelectorAll('thead th[scope="col"]')).map(
        (th) => th.textContent
      )
    ).toEqual(["Señal", "Recibida", "Lectura", "Resultado"]);
    expect(raiz.querySelectorAll('tbody th[scope="row"]')).toHaveLength(3);
    const id = raiz.querySelector("article").getAttribute("aria-labelledby");
    expect(raiz.querySelector('[id="' + id + '"]').textContent).toBe(
      "Lecturas del periodo"
    );
    const controla = boton(elemento, "alternar").getAttribute("aria-controls");
    expect(raiz.querySelector('[id="' + controla + '"]')).not.toBeNull();
  });
});
