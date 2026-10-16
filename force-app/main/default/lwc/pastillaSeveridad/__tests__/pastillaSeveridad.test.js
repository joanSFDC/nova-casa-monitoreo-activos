import { createElement } from "lwc";
import PastillaSeveridad from "c/pastillaSeveridad";

describe("c-pastilla-severidad", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function pastilla(severidad, etiqueta) {
    const el = createElement("c-pastilla-severidad", { is: PastillaSeveridad });
    el.severidad = severidad;
    el.etiqueta = etiqueta;
    document.body.appendChild(el);
    return el.shadowRoot.querySelector(".pastilla");
  }

  it("pinta el crítico con su color y su nombre escrito", () => {
    const span = pastilla("Critico", "Crítico");
    expect(span.classList).toContain("pastilla_critico");
    expect(span.textContent).toContain("Crítico");
  });

  it("nombra la severidad aunque no le pasen la etiqueta", () => {
    expect(pastilla("Advertencia").textContent).toContain("Advertencia");
    expect(pastilla("Normal").classList).toContain("pastilla_normal");
  });

  it("dice sin datos cuando no hay severidad", () => {
    const span = pastilla(undefined);
    expect(span.classList).toContain("pastilla_sin-datos");
    expect(span.textContent).toContain("Sin datos");
  });
});
