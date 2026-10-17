import { createElement } from "lwc";
import ResultadoSenal from "c/resultadoSenal";
import { getRecord } from "lightning/uiRecordApi";

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

function registro(resultado, motivo, reintentable, entregas) {
  return {
    apiName: "Senal__c",
    id: "a07xx0000001",
    fields: {
      Resultado__c: { value: resultado, displayValue: resultado },
      Motivo__c: { value: motivo, displayValue: motivo },
      Reintentable__c: { value: reintentable, displayValue: null },
      Entregas__c: { value: entregas, displayValue: null }
    }
  };
}

describe("c-resultado-senal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function elemento() {
    const el = createElement("c-resultado-senal", { is: ResultadoSenal });
    el.recordId = "a07xx0000001";
    document.body.appendChild(el);
    return el;
  }

  it("pinta un rechazo con su motivo y sus entregas", async () => {
    const el = elemento();
    getRecord.emit(registro("Rechazado", "Valor inválido", false, 2));
    await flushPromises();

    const resultado = el.shadowRoot.querySelector(".resultado");
    expect(resultado.classList).toContain("resultado_rechazado");
    expect(resultado.textContent).toContain("Rechazado");
    expect(el.shadowRoot.textContent).toContain("Valor inválido");
    expect(el.shadowRoot.textContent).toContain("Llegó 2 veces");
    expect(el.shadowRoot.querySelector(".insignia_reintentable")).toBeNull();
    expect(el.shadowRoot.textContent).toContain("No pasó la validación");
  });

  it("avisa cuando la señal se puede reintentar", async () => {
    const el = elemento();
    getRecord.emit(registro("Rechazado", "Activo no encontrado", true, 1));
    await flushPromises();

    expect(
      el.shadowRoot.querySelector(".insignia_reintentable")
    ).not.toBeNull();
    expect(el.shadowRoot.textContent).not.toContain("Llegó 1 veces");
  });

  it("explica qué significa una señal atrasada", async () => {
    const el = elemento();
    getRecord.emit(registro("Atrasado", null, false, 1));
    await flushPromises();

    expect(el.shadowRoot.querySelector(".resultado").classList).toContain(
      "resultado_atrasado"
    );
    expect(el.shadowRoot.textContent).toContain("una lectura más nueva");
  });
});
