import { createElement } from "lwc";
import MonitorDeActivos from "c/monitorDeActivos";
import obtenerPanel from "@salesforce/apex/MonitorControlador.obtenerPanel";
import abrirIntervencion from "@salesforce/apex/MonitorControlador.abrirIntervencion";
import NotaIntervencion from "c/notaIntervencion";
import { subscribe, onError } from "lightning/empApi";
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
  normales: 2,
  sinComunicacion: 1,
  sinEdificios: false,
  sinLecturas: false,
  consultaAtrasada: false,
  puedeAbrir: true,
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
      edificioId: "a01xx0000001",
      ciudad: "Bogotá",
      equipo: "Bomba",
      codigo: "AST-BOG-PUMP-001",
      tipoActivo: "WATER_PUMP",
      tipoActivoEtiqueta: "Bomba de presión",
      medicion: "Presion de agua",
      valor: "0,80 bar",
      lectura: "0,80 bar",
      severidad: "Critico",
      severidadEtiqueta: "Crítico",
      severidadNivel: 2,
      puedeIntervenir: true,
      antiguedad: "hace 40 min",
      fechaOrigen: "2026-10-16T10:00:00.000Z",
      esCamara: false,
      comunicacionEstado: null,
      comunicacion: null,
      casoNormalizado: false
    },
    {
      estadoId: "a08xx0000002",
      activoId: "a03xx0000002",
      casoId: null,
      edificio: "Edificio Nova Alameda",
      edificioId: "a01xx0000001",
      ciudad: "Bogotá",
      equipo: "Camara",
      codigo: "AST-BOG-CAM-001",
      tipoActivo: "SECURITY_CAMERA",
      tipoActivoEtiqueta: "Cámara de seguridad",
      medicion: "Conectividad",
      valor: "90 s",
      lectura: "Sin comunicación · 1 min",
      severidad: "Normal",
      severidadEtiqueta: "Normal",
      severidadNivel: 0,
      puedeIntervenir: false,
      antiguedad: "hace 5 min",
      fechaOrigen: "2026-10-16T09:00:00.000Z",
      esCamara: true,
      comunicacionEstado: "LOST",
      comunicacion: "Sin comunicacion",
      casoNormalizado: false
    },
    {
      estadoId: "a08xx0000003",
      activoId: "a03xx0000003",
      casoId: "500xx0000009",
      edificio: "Edificio Nova Caribe",
      edificioId: "a01xx0000002",
      ciudad: "Barranquilla",
      equipo: "Sala técnica",
      codigo: "AST-BAQ-TEMP-001",
      tipoActivo: "TECHNICAL_ROOM",
      tipoActivoEtiqueta: "Sala técnica",
      medicion: "Temperatura",
      valor: "26,8 °C",
      lectura: "26,8 °C",
      severidad: "Normal",
      severidadEtiqueta: "Normal",
      severidadNivel: 0,
      puedeIntervenir: true,
      antiguedad: "hace 10 min",
      fechaOrigen: "2026-10-16T10:20:00.000Z",
      esCamara: false,
      comunicacionEstado: null,
      comunicacion: null,
      casoNormalizado: true
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

    expect(el.shadowRoot.querySelectorAll("tr.fila-equipo")).toHaveLength(3);
    expect(el.shadowRoot.textContent).toContain("Bomba");

    expect(subscribe).toHaveBeenCalled();
    expect(subscribe.mock.calls[0][0]).toBe("/event/Panel_Actualizado__e");
    const callback = subscribe.mock.calls[0][2];
    callback({ data: { payload: { Codigo_Activo__c: "SECRETO-BAQ" } } });
    expect(el.shadowRoot.textContent).not.toContain("SECRETO-BAQ");
  });

  it("avisa si la actualización automática no está disponible", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();
    expect(el.shadowRoot.querySelector(".aviso-tiempo-real")).toBeNull();

    onError.mock.calls[0][0]({ error: "403::Unknown client" });
    await flushPromises();

    expect(el.shadowRoot.querySelector(".aviso-tiempo-real")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector('[aria-live="polite"]').textContent
    ).toContain("La actualización automática no está disponible");

    subscribe.mock.calls[0][2]({ data: { payload: {} } });
    await flushPromises();
    expect(el.shadowRoot.querySelector(".aviso-tiempo-real")).toBeNull();
  });

  it("avisa si la suscripción no se completa", async () => {
    subscribe.mockImplementationOnce(() =>
      Promise.reject(new Error("handshake"))
    );
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    expect(el.shadowRoot.querySelector(".aviso-tiempo-real")).not.toBeNull();
  });

  it("solo ofrece intervenir donde hay algo que atender", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const filas = el.shadowRoot.querySelectorAll("tr.fila-equipo");
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

    expect(el.shadowRoot.querySelectorAll("tr.fila-equipo")).toHaveLength(1);
    expect(el.shadowRoot.textContent).toContain("Bomba");
    expect(el.shadowRoot.textContent).not.toContain("Camara");
  });

  function filasVisibles(el) {
    return Array.from(el.shadowRoot.querySelectorAll("tr.fila-equipo"));
  }

  function nombres(el) {
    return filasVisibles(el).map((fila) =>
      fila.querySelector(".equipo-nombre").textContent.trim()
    );
  }

  function cambiar(el, selector, valor) {
    el.shadowRoot
      .querySelector(selector)
      .dispatchEvent(new CustomEvent("change", { detail: { value: valor } }));
  }

  it("agrupa por edificio con su ciudad y su resumen", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const grupos = el.shadowRoot.querySelectorAll("tr.fila-grupo");
    expect(grupos).toHaveLength(2);
    expect(grupos[0].textContent).toContain("Edificio Nova Alameda");
    expect(grupos[0].textContent).toContain("Bogotá");
    expect(grupos[0].textContent).toContain("1 crítico · 1 sin comunicación");
    expect(grupos[1].textContent).toContain("Barranquilla");
    expect(grupos[1].textContent).toContain("Todo normal");
    expect(grupos[0].querySelector('th[scope="rowgroup"]')).not.toBeNull();
  });

  it("dibuja el ícono del tipo de cada equipo", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const iconos = el.shadowRoot.querySelectorAll("c-icono-equipo");
    expect(iconos).toHaveLength(3);
    expect(iconos[0].tipo).toBe("WATER_PUMP");
    expect(iconos[1].tipo).toBe("SECURITY_CAMERA");
    expect(filasVisibles(el)[0].textContent).toContain(
      "Bomba de presión · AST-BOG-PUMP-001"
    );
  });

  it("dice la comunicación solo en las cámaras, sin columna aparte", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const cabeceras = Array.from(
      el.shadowRoot.querySelectorAll("thead th")
    ).map((th) => th.textContent.trim());
    expect(cabeceras).not.toContain("Comunicación");
    const [bomba, camara] = filasVisibles(el);
    expect(bomba.querySelector(".comunicacion")).toBeNull();
    expect(bomba.querySelector(".valor").textContent).toBe("0,80 bar");
    const ficha = camara.querySelector(".comunicacion_perdida");
    expect(ficha).not.toBeNull();
    expect(ficha.textContent).toContain("Sin comunicación · 1 min");
  });

  it("dice normalizado cuando el equipo volvió a lo normal con el caso abierto", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const [bomba, , sala] = filasVisibles(el);
    expect(bomba.querySelector(".insignia-normalizado")).toBeNull();
    const insignia = sala.querySelector(".insignia-normalizado");
    expect(insignia).not.toBeNull();
    expect(insignia.textContent).toContain("Normalizado · caso abierto");
    expect(sala.querySelector("lightning-button").label).toBe("Ver incidente");
  });

  it("pasa la severidad a la pastilla de cada fila", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const pastilla = filasVisibles(el)[0].querySelector("c-pastilla-severidad");
    expect(pastilla.severidad).toBe("Critico");
    expect(pastilla.etiqueta).toBe("Crítico");
  });

  it("filtra por tipo de equipo", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const tipo = el.shadowRoot.querySelector(".control_tipo");
    expect(tipo.options.map((o) => o.value)).toEqual([
      "",
      "WATER_PUMP",
      "SECURITY_CAMERA",
      "TECHNICAL_ROOM"
    ]);
    cambiar(el, ".control_tipo", "SECURITY_CAMERA");
    await flushPromises();
    expect(nombres(el)).toEqual(["Camara"]);
  });

  it("busca por nombre o código sin importar las tildes", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    cambiar(el, ".control_busqueda", "tecnica");
    await flushPromises();
    expect(nombres(el)).toEqual(["Sala técnica"]);

    cambiar(el, ".control_busqueda", "bog-pump");
    await flushPromises();
    expect(nombres(el)).toEqual(["Bomba"]);
  });

  it("ordena por antigüedad dentro de cada edificio", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();
    expect(nombres(el)).toEqual(["Bomba", "Camara", "Sala técnica"]);

    cambiar(el, ".control_orden", "antiguedad");
    await flushPromises();
    expect(nombres(el)).toEqual(["Camara", "Bomba", "Sala técnica"]);
  });

  it("la ficha sin comunicación deja solo los cortes", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    const ficha = el.shadowRoot.querySelector(
      '[data-severidad="SinComunicacion"]'
    );
    expect(ficha.textContent).toContain("1 sin comunicación");
    ficha.click();
    await flushPromises();
    expect(nombres(el)).toEqual(["Camara"]);
    expect(
      el.shadowRoot
        .querySelector('[data-severidad="SinComunicacion"]')
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("sin resultados ofrece quitar los filtros", async () => {
    const el = elemento();
    obtenerPanel.emit(PANEL);
    await flushPromises();

    cambiar(el, ".control_busqueda", "no existe");
    await flushPromises();
    expect(el.shadowRoot.textContent).toContain(
      "Ningún equipo coincide con los filtros"
    );
    const quitar = Array.from(
      el.shadowRoot.querySelectorAll("lightning-button")
    ).find((boton) => boton.label === "Quitar filtros");
    quitar.click();
    await flushPromises();
    expect(filasVisibles(el)).toHaveLength(3);
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
