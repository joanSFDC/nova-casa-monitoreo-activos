import { createElement } from "lwc";
import ResumenIncidente from "c/resumenIncidente";
import incidente from "@salesforce/apex/ResumenRegistroControlador.incidente";

jest.mock(
  "@salesforce/apex/ResumenRegistroControlador.incidente",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const RESUMEN = {
  medicion: "Presión de agua",
  cerrado: false,
  normalizado: true,
  normalizadoEn: "2026-10-16T10:30:00.000Z",
  equipo: {
    activoId: "a03xx0000001",
    nombre: "Bomba de presión de agua",
    codigo: "AST-BAQ-PUMP-001",
    tipo: "WATER_PUMP",
    tipoEtiqueta: "Bomba de presión",
    edificioId: "a01xx0000002",
    edificio: "Edificio Nova Caribe",
    ciudad: "Barranquilla"
  },
  apertura: {
    texto: "5,50 bar",
    severidad: "Critico",
    severidadEtiqueta: "Crítico",
    fecha: "2026-10-16T10:00:00.000Z"
  },
  ultima: {
    texto: "3,80 bar",
    severidad: "Normal",
    severidadEtiqueta: "Normal",
    fecha: "2026-10-16T10:30:00.000Z"
  },
  ahora: {
    lectura: "3,75 bar",
    severidad: "Normal",
    severidadEtiqueta: "Normal",
    antiguedad: "hace 2 min"
  }
};

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

describe("c-resumen-incidente", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function elemento() {
    const el = createElement("c-resumen-incidente", { is: ResumenIncidente });
    el.recordId = "500xx0000001";
    document.body.appendChild(el);
    return el;
  }

  it("muestra lo que abrió el caso, su último cambio y cómo está ahora", async () => {
    const el = elemento();
    incidente.emit(RESUMEN);
    await flushPromises();

    const lecturas = el.shadowRoot.querySelectorAll(".lectura");
    expect(lecturas).toHaveLength(3);
    expect(lecturas[0].textContent).toContain("Lo abrió");
    expect(lecturas[0].textContent).toContain("5,50 bar");
    expect(lecturas[1].textContent).toContain("Último cambio");
    expect(lecturas[1].textContent).toContain("3,80 bar");
    expect(lecturas[2].textContent).toContain("Ahora");
    expect(lecturas[2].textContent).toContain("hace 2 min");
    expect(lecturas[0].querySelector("c-pastilla-severidad").severidad).toBe(
      "Critico"
    );
    expect(el.shadowRoot.textContent).toContain("Edificio Nova Caribe");
  });

  it("explica que el equipo se normalizó y el caso sigue abierto", async () => {
    const el = elemento();
    incidente.emit(RESUMEN);
    await flushPromises();

    const aviso = el.shadowRoot.querySelector(".normalizado");
    expect(aviso).not.toBeNull();
    expect(aviso.textContent).toContain("volvió a lo normal");
    expect(aviso.textContent).toContain("hasta que coordinación lo verifique");
  });

  it("no avisa de normalizado en un caso cerrado", async () => {
    const el = elemento();
    incidente.emit({ ...RESUMEN, cerrado: true });
    await flushPromises();
    expect(el.shadowRoot.querySelector(".normalizado")).toBeNull();
  });

  it("dice sin registro en un caso anterior a las lecturas", async () => {
    const el = elemento();
    incidente.emit({ ...RESUMEN, apertura: null, ultima: null });
    await flushPromises();
    const vacias = el.shadowRoot.querySelectorAll(".lectura-vacia");
    expect(vacias).toHaveLength(2);
  });

  it("no muestra nada si el servidor no le deja ver el caso", async () => {
    const el = elemento();
    incidente.emit(null);
    await flushPromises();
    expect(el.shadowRoot.querySelector(".tarjeta")).toBeNull();
  });

  it("explica el error si el servidor falla", async () => {
    const el = elemento();
    incidente.error();
    await flushPromises();
    expect(el.shadowRoot.textContent).toContain("No se pudo cargar");
  });
});
