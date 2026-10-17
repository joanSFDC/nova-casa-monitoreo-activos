import { createElement } from "lwc";
import ResumenEdificio from "c/resumenEdificio";
import edificio from "@salesforce/apex/ResumenRegistroControlador.edificio";

jest.mock(
  "@salesforce/apex/ResumenRegistroControlador.edificio",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const RESUMEN = {
  nombre: "Edificio Nova Caribe",
  ciudad: "Barranquilla",
  region: "Caribe",
  criticos: 1,
  advertencias: 0,
  normales: 1,
  sinComunicacion: 0,
  equipos: [
    {
      estadoId: "a08xx0000001",
      activoId: "a03xx0000001",
      equipo: "Sala técnica principal",
      tipoActivo: "TECHNICAL_ROOM",
      medicion: "Temperatura",
      lectura: "37,3 °C",
      esCamara: false,
      severidad: "Critico",
      severidadEtiqueta: "Crítico",
      casoNormalizado: false
    },
    {
      estadoId: "a08xx0000002",
      activoId: "a03xx0000002",
      equipo: "Bomba de presión de agua",
      tipoActivo: "WATER_PUMP",
      medicion: "Presión de agua",
      lectura: "3,80 bar",
      esCamara: false,
      severidad: "Normal",
      severidadEtiqueta: "Normal",
      casoNormalizado: true
    }
  ],
  casos: [
    {
      id: "500xx0000001",
      numero: "00001210",
      equipo: "Sala técnica principal",
      prioridad: "Alta",
      normalizado: false,
      ultimaLectura: "37,3 °C"
    }
  ]
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

describe("c-resumen-edificio", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function elemento() {
    const el = createElement("c-resumen-edificio", { is: ResumenEdificio });
    el.recordId = "a01xx0000002";
    document.body.appendChild(el);
    return el;
  }

  it("cuenta los equipos por severidad con su color", async () => {
    const el = elemento();
    edificio.emit(RESUMEN);
    await flushPromises();

    const conteos = el.shadowRoot.querySelectorAll(".conteo");
    expect(conteos).toHaveLength(4);
    expect(conteos[0].textContent).toContain("1 crítico");
    expect(conteos[0].classList).toContain("conteo_critico");
    expect(conteos[1].classList).toContain("conteo_vacio");
    expect(el.shadowRoot.textContent).toContain("Barranquilla · Caribe");
  });

  it("lista sus equipos con ícono, lectura y normalizado", async () => {
    const el = elemento();
    edificio.emit(RESUMEN);
    await flushPromises();

    const iconos = el.shadowRoot.querySelectorAll("c-icono-equipo");
    expect(iconos).toHaveLength(2);
    expect(iconos[0].tipo).toBe("TECHNICAL_ROOM");
    expect(el.shadowRoot.textContent).toContain("37,3 °C");
    expect(
      el.shadowRoot.querySelectorAll(".insignia-normalizado")
    ).toHaveLength(1);
  });

  it("lista sus incidentes abiertos con la última lectura", async () => {
    const el = elemento();
    edificio.emit(RESUMEN);
    await flushPromises();

    expect(el.shadowRoot.textContent).toContain("00001210");
    expect(el.shadowRoot.textContent).toContain("última lectura 37,3 °C");
    expect(el.shadowRoot.querySelector(".insignia-falla")).not.toBeNull();
  });
});
