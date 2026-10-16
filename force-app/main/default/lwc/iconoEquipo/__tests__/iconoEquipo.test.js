import { createElement } from "lwc";
import IconoEquipo from "c/iconoEquipo";

describe("c-icono-equipo", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function icono(tipo) {
    const el = createElement("c-icono-equipo", { is: IconoEquipo });
    el.tipo = tipo;
    document.body.appendChild(el);
    return el.shadowRoot.querySelector(".icono");
  }

  it.each([
    ["WATER_PUMP", "icono_bomba"],
    ["WATER_METER", "icono_agua"],
    ["ENERGY_METER", "icono_energia"],
    ["TECHNICAL_ROOM", "icono_sala"],
    ["SECURITY_CAMERA", "icono_camara"]
  ])("dibuja %s con su propio ícono", (tipo, clase) => {
    const span = icono(tipo);
    expect(span.classList).toContain(clase);
    expect(span.querySelector("svg")).not.toBeNull();
  });

  it("usa un ícono genérico para un tipo que no conoce", () => {
    expect(icono("ELEVATOR").classList).toContain("icono_otro");
  });

  it("no se anuncia: el tipo va escrito al lado", () => {
    expect(icono("WATER_PUMP").getAttribute("aria-hidden")).toBe("true");
  });
});
