import { createElement } from "lwc";
import HistoriaIncidente, { TOPE_MAXIMO } from "c/historiaIncidente";
import historia from "@salesforce/apex/HistoriaIncidenteControlador.historia";
import { registerRefreshHandler } from "lightning/refresh";

jest.mock(
  "@salesforce/apex/HistoriaIncidenteControlador.historia",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const HISTORIA = {
  abiertas: [
    {
      id: "00Txx0000001",
      asunto: "Revisar la presión de la bomba",
      responsable: "Coordinador Mantenimiento",
      estado: "No iniciada",
      fechaLimite: "2026-10-23",
      prioridad: "Alta"
    }
  ],
  eventos: [
    {
      clave: "Priority|1",
      tipo: "critico",
      fecha: "2026-10-22T20:40:00.000Z",
      campo: "Prioridad",
      antes: "Baja",
      despues: "Alta",
      quien: "Sistema"
    },
    {
      clave: "00Txx0000002",
      tipo: "intervencion",
      fecha: "2026-10-22T18:15:00.000Z",
      texto: "Intervención completada: «Cambiar el manómetro»",
      quien: "Operador Barranquilla"
    },
    {
      clave: "created|1",
      tipo: "apertura",
      fecha: "2026-10-20T14:30:00.000Z",
      texto: "Se abrió el incidente",
      quien: "Sistema"
    }
  ],
  hayMas: true
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

function crear() {
  const elemento = createElement("c-historia-incidente", {
    is: HistoriaIncidente
  });
  elemento.recordId = "500xx0000001";
  document.body.appendChild(elemento);
  return elemento;
}

describe("c-historia-incidente", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("muestra las intervenciones abiertas y la línea de tiempo en orden", async () => {
    const elemento = crear();
    historia.emit(HISTORIA);
    await flushPromises();

    const raiz = elemento.shadowRoot;
    expect(raiz.querySelector(".titulo").textContent).toBe(
      "Historia del incidente"
    );
    expect(raiz.querySelector(".seccion").textContent).toBe(
      "Intervenciones abiertas (1)"
    );
    const intervencion = raiz.querySelector(".intervencion");
    expect(intervencion.textContent).toContain(
      "Revisar la presión de la bomba"
    );
    expect(intervencion.textContent).toContain("Coordinador Mantenimiento");

    const eventos = raiz.querySelectorAll(".linea li");
    expect(eventos).toHaveLength(3);
    expect(eventos[0].classList).toContain("evento_critico");
    expect(eventos[0].querySelector(".que").textContent.trim()).toBe(
      "Prioridad: Baja a Alta"
    );
    expect(eventos[0].querySelector(".quien").textContent).toBe("Sistema");
    expect(eventos[1].classList).toContain("evento_intervencion");
    expect(eventos[1].textContent).toContain("Cambiar el manómetro");
    expect(eventos[2].textContent).toContain("Se abrió el incidente");
  });

  it("pide toda la historia al pulsar Ver toda la historia", async () => {
    const elemento = crear();
    historia.emit(HISTORIA);
    await flushPromises();

    elemento.shadowRoot.querySelector(".ver-todo").click();
    await flushPromises();

    expect(historia.getLastConfig()).toEqual({
      casoId: "500xx0000001",
      tope: TOPE_MAXIMO
    });
    expect(elemento.shadowRoot.querySelectorAll(".linea li")).toHaveLength(3);
  });

  it("avisa cuando no hay intervenciones ni cambios", async () => {
    const elemento = crear();
    historia.emit({ abiertas: [], eventos: [], hayMas: false });
    await flushPromises();

    const textos = Array.from(
      elemento.shadowRoot.querySelectorAll(".vacio")
    ).map((p) => p.textContent);
    expect(textos).toEqual([
      "No hay intervenciones abiertas.",
      "Todavía no hay cambios registrados."
    ]);
    expect(elemento.shadowRoot.querySelector(".ver-todo")).toBeNull();
  });

  it("muestra el error cuando no carga", async () => {
    const elemento = crear();
    historia.error();
    await flushPromises();

    expect(
      elemento.shadowRoot.querySelector('[role="alert"]').textContent
    ).toBe("No se pudo cargar la historia del incidente.");
  });

  it("se registra para recargarse cuando la página se actualiza", () => {
    crear();
    expect(registerRefreshHandler).toHaveBeenCalledTimes(1);
  });

  it("nombra cada sección y dice el tipo de evento sin depender del color", async () => {
    const elemento = crear();
    historia.emit(HISTORIA);
    await flushPromises();

    const raiz = elemento.shadowRoot;
    const titulados = raiz.querySelectorAll(
      "article[aria-labelledby], section[aria-labelledby]"
    );
    expect(titulados).toHaveLength(3);
    titulados.forEach((nodo) => {
      const id = nodo.getAttribute("aria-labelledby");
      expect(raiz.querySelector('[id="' + id + '"]')).not.toBeNull();
    });
    const tipos = Array.from(
      raiz.querySelectorAll(".linea li .slds-assistive-text")
    ).map((span) => span.textContent);
    expect(tipos).toEqual([
      "Cambio crítico:",
      "Intervención cerrada:",
      "Apertura:"
    ]);
    const boton = raiz.querySelector(".ver-todo");
    expect(boton.tagName).toBe("BUTTON");
    expect(boton.getAttribute("type")).toBe("button");
  });
});
