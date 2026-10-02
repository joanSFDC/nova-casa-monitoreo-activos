import { createElement } from "lwc";
import NotaIntervencion from "c/notaIntervencion";

describe("c-nota-intervencion", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function dialogo() {
    const el = createElement("c-nota-intervencion", { is: NotaIntervencion });
    el.equipo = "Bomba · Presión de agua";
    document.body.appendChild(el);
    return el;
  }

  function boton(el, etiqueta) {
    return Array.from(el.shadowRoot.querySelectorAll("lightning-button")).find(
      (b) => b.label === etiqueta
    );
  }

  function escribir(el, texto) {
    const campo = el.shadowRoot.querySelector("lightning-textarea");
    campo.dispatchEvent(
      new CustomEvent("change", { detail: { value: texto } })
    );
  }

  it("titula el diálogo y etiqueta la nota", () => {
    const el = dialogo();
    const cabecera = el.shadowRoot.querySelector("lightning-modal-header");
    expect(cabecera.label).toBe("Abrir intervención");
    const campo = el.shadowRoot.querySelector("lightning-textarea");
    expect(campo.label).toBe("Nota para la actividad del caso (opcional)");
  });

  it("devuelve la nota escrita al abrir", () => {
    const el = dialogo();
    escribir(el, "  Revisar la bomba  ");
    boton(el, "Abrir").click();
    expect(el.close).toHaveBeenCalledWith({ nota: "Revisar la bomba" });
  });

  it("abre sin nota si el campo queda en blanco", () => {
    const el = dialogo();
    escribir(el, "   ");
    boton(el, "Abrir").click();
    expect(el.close).toHaveBeenCalledWith({ nota: null });
  });

  it("cancelar cierra sin resultado", () => {
    const el = dialogo();
    escribir(el, "No la quiero");
    boton(el, "Cancelar").click();
    expect(el.close).toHaveBeenCalledWith();
  });
});
