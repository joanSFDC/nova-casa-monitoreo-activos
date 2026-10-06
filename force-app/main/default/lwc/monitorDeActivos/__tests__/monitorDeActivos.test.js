import { createElement } from "lwc";
import MonitorDeActivos from "c/monitorDeActivos";
import obtenerPanel from "@salesforce/apex/MonitorControlador.obtenerPanel";
import abrirIntervencion from "@salesforce/apex/MonitorControlador.abrirIntervencion";
import NotaIntervencion from "c/notaIntervencion";
import { subscribe } from "lightning/empApi";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/apex/MonitorControlador.obtenerPanel",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/MonitorControlador.abrirIntervencion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  "lightning/empApi",
  () => ({
    subscribe: jest.fn(() => Promise.resolve({ id: "sub" })),
    unsubscribe: jest.fn(() => Promise.resolve()),
    onError: jest.fn()
  }),
  { virtual: true }
);

const PANEL = {
  criticos: 1,
  advertencias: 0,
  normales: 1,
  sinEdificios: false,
  sinLecturas: false,
  consultaAtrasada: false,
  edificios: [
    { id: "a01xx0000001", nombre: "Edificio Nova Alameda" },
    { id: "a01xx0000002", nombre: "Edificio Nova Caribe" }
  ],
  filas: [
    {
      estadoId: "a08xx0000001",
      activoId: "a03xx0000001",
      casoId: null,
      edificio: "Edificio Nova Alameda",
      equipo: "Bomba",
      medicion: "Presion de agua",
      valor: "0,80 bar",
      severidad: "Critico",
      severidadEtiqueta: "Crítico",
      severidadNivel: 2,
      puedeIntervenir: true,
      antiguedad: "hace 40 min",
      comunicacion: null
    },
    {
      estadoId: "a08xx0000002",
      activoId: "a03xx0000002",
      casoId: null,
      edificio: "Edificio Nova Alameda",
      equipo: "Camara",
      medicion: "Conectividad",
      valor: "90 s",
      severidad: "Normal",
      severidadEtiqueta: "Normal",
      severidadNivel: 0,
      puedeIntervenir: false,
      antiguedad: "hace 5 min",
      comunicacion: "Sin comunicacion"
    }
  ]
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

describe("c-monitor-de-activos", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function elemento() {
    const el = createElement("c-monitor-de-activos", {
      is: MonitorDeActivos
    });
    document.body.appendChild(el);
    return el;
  }

  it("muestra el esqueleto mientras carga", () => {
    const el = elemento();
    expect(el.shadowRoot.textContent).toContain("Cargando el monitor");
  });

  it("pinta filas y no usa el contenido del timbre", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(2);
    expect(el.shadowRoot.textContent).toContain("Bomba");

    expect(subscribe).toHaveBeenCalled();
    expect(subscribe.mock.calls[0][0]).toBe("/event/Panel_Actualizado__e");
    const callback = subscribe.mock.calls[0][2];
    callback({ data: { payload: { Codigo_Activo__c: "SECRETO-BAQ" } } });
    expect(el.shadowRoot.textContent).not.toContain("SECRETO-BAQ");
  });

  it("solo ofrece intervenir donde hay algo que atender", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const filas = el.shadowRoot.querySelectorAll("tbody tr");
    expect(filas[0].querySelector("lightning-button")).not.toBeNull();
    expect(filas[1].querySelector("lightning-button")).toBeNull();
    expect(el.shadowRoot.textContent).toContain("1 crítico");
    expect(el.shadowRoot.textContent).not.toContain("1 críticos");
  });

  it("distingue equipos sin lecturas", async () => {
    const el = elemento();
    obtenerPanel.emit({
      ...PANEL,
      filas: [],
      criticos: 0,
      advertencias: 0,
      normales: 0,
      sinLecturas: true
    });
    await flushPromises();
    expect(el.shadowRoot.textContent).toContain(
      "Tus equipos no tienen lecturas"
    );
  });

  it("filtra por severidad sobre datos ya autorizados", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    el.shadowRoot.querySelector('[data-severidad="Critico"]').click();
    await flushPromises();

    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
    expect(el.shadowRoot.textContent).toContain("Bomba");
    expect(el.shadowRoot.textContent).not.toContain("Camara");
  });

  async function pulsarIntervenir(respuesta) {
    NotaIntervencion.open.mockResolvedValue(respuesta);
    abrirIntervencion.mockResolvedValue("500xx0000001");
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();
    el.shadowRoot
      .querySelector('lightning-button[data-estado="a08xx0000001"]')
      .click();
    await flushPromises();
    return el;
  }

  it("pide la nota antes de abrir la intervención y la envía", async () => {
    await pulsarIntervenir({ nota: "Revisar la bomba" });

    expect(NotaIntervencion.open).toHaveBeenCalledWith(
      expect.objectContaining({ equipo: "Bomba · Presion de agua" })
    );
    expect(abrirIntervencion).toHaveBeenCalledWith({
      estadoId: "a08xx0000001",
      nota: "Revisar la bomba"
    });
  });

  it("abre la intervención sin nota si se deja en blanco", async () => {
    await pulsarIntervenir({ nota: null });

    expect(abrirIntervencion).toHaveBeenCalledWith({
      estadoId: "a08xx0000001",
      nota: null
    });
  });

  it("cancelar el diálogo no abre nada", async () => {
    await pulsarIntervenir(undefined);

    expect(NotaIntervencion.open).toHaveBeenCalled();
    expect(abrirIntervencion).not.toHaveBeenCalled();
  });

  describe("vigilancia y anuncios", () => {
    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.clearAllTimers();
      jest.useRealTimers();
      refreshApex.mockReset();
      refreshApex.mockImplementation(() => Promise.resolve());
    });

    async function microtareas() {
      for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop -- una vuelta por promesa encadenada
        await Promise.resolve();
      }
    }

    function region(el) {
      return el.shadowRoot.querySelector('[aria-live="polite"]').textContent;
    }

    function botonActualizar(el) {
      return Array.from(
        el.shadowRoot.querySelectorAll("lightning-button")
      ).find((boton) => boton.label === "Actualizar");
    }

    async function montado() {
      const el = elemento();
      obtenerPanel.emit(PANEL);
      await microtareas();
      return el;
    }

    it("vuelve a consultar sola si pasa un minuto sin consultas", async () => {
      await montado();
      expect(refreshApex).not.toHaveBeenCalled();

      jest.advanceTimersByTime(60000);
      await microtareas();
      expect(refreshApex).toHaveBeenCalledTimes(1);

      jest.advanceTimersByTime(60000);
      await microtareas();
      expect(refreshApex).toHaveBeenCalledTimes(2);
    });

    it("una consulta por timbre reinicia la vigilancia", async () => {
      await montado();
      jest.advanceTimersByTime(50000);
      subscribe.mock.calls[0][2]({ data: { payload: {} } });
      jest.advanceTimersByTime(2000);
      await microtareas();
      expect(refreshApex).toHaveBeenCalledTimes(1);

      jest.advanceTimersByTime(50000);
      await microtareas();
      expect(refreshApex).toHaveBeenCalledTimes(1);

      jest.advanceTimersByTime(10000);
      await microtareas();
      expect(refreshApex).toHaveBeenCalledTimes(2);
    });

    it("la vigilancia solo anuncia si cambia el aviso de atraso", async () => {
      const el = await montado();
      const inicial = region(el);
      expect(inicial).toContain("Monitor actualizado a las");

      jest.advanceTimersByTime(60000);
      await microtareas();
      expect(region(el)).toBe(inicial);

      refreshApex.mockImplementationOnce(() => {
        obtenerPanel.emit({ ...PANEL, consultaAtrasada: true });
        return Promise.resolve();
      });
      jest.advanceTimersByTime(60000);
      await microtareas();
      expect(region(el)).toContain("se atrasó");
      expect(el.shadowRoot.querySelector(".slds-alert_warning")).not.toBeNull();
    });

    it("anuncia cada actualización por botón", async () => {
      const el = await montado();
      let terminar;
      refreshApex.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            terminar = resolve;
          })
      );

      botonActualizar(el).click();
      await microtareas();
      expect(region(el)).toBe("Actualizando el monitor");

      terminar();
      await microtareas();
      expect(region(el)).toContain("Monitor actualizado a las");
    });

    it("anuncia el error de una actualización", async () => {
      const el = await montado();
      refreshApex.mockImplementationOnce(() =>
        Promise.reject({ body: { message: "Servidor caído" } })
      );

      botonActualizar(el).click();
      await microtareas();
      expect(region(el)).toBe(
        "No se pudo actualizar el monitor. Servidor caído"
      );
    });

    it("deja de vigilar al desmontar", async () => {
      const el = await montado();
      document.body.removeChild(el);

      jest.advanceTimersByTime(120000);
      await microtareas();
      expect(refreshApex).not.toHaveBeenCalled();
    });
  });
});
