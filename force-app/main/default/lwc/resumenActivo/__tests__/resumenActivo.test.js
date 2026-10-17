import { createElement } from "lwc";
import ResumenActivo from "c/resumenActivo";
import activo from "@salesforce/apex/ResumenRegistroControlador.activo";

jest.mock(
  "@salesforce/apex/ResumenRegistroControlador.activo",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const RESUMEN = {
  severidad: "Advertencia",
  severidadEtiqueta: "Advertencia",
  equipo: {
    activoId: "a03xx0000002",
    nombre: "Cámara azotea",
    codigo: "AST-BAQ-CAM-001",
    tipo: "SECURITY_CAMERA",
    tipoEtiqueta: "Cámara de seguridad",
    edificioId: "a01xx0000002",
    edificio: "Edificio Nova Caribe",
    ciudad: "Barranquilla"
  },
  mediciones: [
    {
      estadoId: "a08xx0000002",
      medicion: "Conectividad",
      lectura: "Sin comunicación · 15 min",
      esCamara: true,
      comunicacionEstado: "LOST",
      severidad: "Advertencia",
      severidadEtiqueta: "Advertencia",
      nivel: 1,
      antiguedad: "hace 1 min",
      casoNormalizado: false
    }
  ],
  casos: [
    {
      id: "500xx0000002",
      numero: "00001220",
      asunto: "Corte de comunicación EPI-1",
      prioridad: "Baja",
      normalizado: false,
      enFalla: true,
      ultimaLectura: "Sin comunicación · 15 min"
    }
  ],
  limites: [
    {
      tipoMedicion: "CAMERA_CONNECTIVITY",
      medicion: "Conectividad",
      minutosAdvertencia: 15,
      minutosCritico: 60
    }
  ]
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

describe("c-resumen-activo", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function elemento() {
    const el = createElement("c-resumen-activo", { is: ResumenActivo });
    el.recordId = "a03xx0000002";
    document.body.appendChild(el);
    return el;
  }

  it("junta en una tarjeta el equipo, sus mediciones, sus casos y sus límites", async () => {
    const el = elemento();
    activo.emit(RESUMEN);
    await flushPromises();

    expect(el.shadowRoot.querySelector("c-icono-equipo").tipo).toBe(
      "SECURITY_CAMERA"
    );
    expect(el.shadowRoot.textContent).toContain(
      "Cámara de seguridad · AST-BAQ-CAM-001"
    );
    expect(el.shadowRoot.querySelector(".edificio").textContent).toContain(
      "Edificio Nova Caribe · Barranquilla"
    );
    expect(el.shadowRoot.textContent).toContain(
      "Prioridad Baja · última lectura Sin comunicación · 15 min"
    );
    const corte = el.shadowRoot.querySelector(".comunicacion_perdida");
    expect(corte.textContent).toContain("Sin comunicación · 15 min");
    expect(el.shadowRoot.textContent).toContain("00001220");
    expect(el.shadowRoot.querySelector(".insignia-falla")).not.toBeNull();
    const bandas = el.shadowRoot.querySelector("c-bandas-umbral");
    expect(bandas.limite.minutosCritico).toBe(60);
    expect(bandas.compacto).toBe(true);
  });

  it("dice normalizado en el caso y en la medición que volvió", async () => {
    const el = elemento();
    activo.emit({
      ...RESUMEN,
      mediciones: [{ ...RESUMEN.mediciones[0], casoNormalizado: true }],
      casos: [{ ...RESUMEN.casos[0], normalizado: true }]
    });
    await flushPromises();
    expect(
      el.shadowRoot.querySelectorAll(".insignia-normalizado")
    ).toHaveLength(2);
  });

  it("no dice en falla de un caso anterior a las lecturas", async () => {
    const el = elemento();
    activo.emit({
      ...RESUMEN,
      casos: [{ ...RESUMEN.casos[0], enFalla: false, normalizado: false }]
    });
    await flushPromises();
    expect(el.shadowRoot.querySelector(".insignia-falla")).toBeNull();
  });

  it("explica cuando no hay lecturas ni casos", async () => {
    const el = elemento();
    activo.emit({ ...RESUMEN, mediciones: [], casos: [], limites: [] });
    await flushPromises();
    expect(el.shadowRoot.textContent).toContain("todavía no tiene lecturas");
    expect(el.shadowRoot.textContent).toContain("Sin incidentes abiertos");
    expect(el.shadowRoot.querySelector("c-bandas-umbral")).toBeNull();
  });
});
