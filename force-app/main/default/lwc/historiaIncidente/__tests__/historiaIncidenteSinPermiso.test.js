import { createElement } from "lwc";
import HistoriaIncidente from "c/historiaIncidente";
import historia from "@salesforce/apex/HistoriaIncidenteControlador.historia";

jest.mock(
  "@salesforce/apex/HistoriaIncidenteControlador.historia",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// El permiso se lee al cargar el componente: sin él va en un archivo aparte.
jest.mock(
  "@salesforce/customPermission/Nova_Casa_Registrar_Intervencion",
  () => ({ default: false }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

describe("c-historia-incidente sin el permiso de registrar intervenciones", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("muestra la intervención abierta sin ofrecer completarla", async () => {
    const elemento = createElement("c-historia-incidente", {
      is: HistoriaIncidente
    });
    elemento.recordId = "500xx0000001";
    document.body.appendChild(elemento);
    historia.emit({
      abiertas: [
        {
          id: "00Txx0000001",
          asunto: "Revisar el equipo en sitio",
          responsable: "Coordinador Mantenimiento",
          estado: "No iniciada",
          fechaLimite: "2026-10-30",
          prioridad: "Alta"
        }
      ],
      eventos: [],
      hayMas: false
    });
    await flushPromises();

    const raiz = elemento.shadowRoot;
    expect(raiz.querySelector(".intervencion .asunto").textContent).toBe(
      "Revisar el equipo en sitio"
    );
    expect(raiz.querySelector("button.completar")).toBeNull();
  });
});
