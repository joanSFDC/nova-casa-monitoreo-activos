import { createElement } from "lwc";
import BandasUmbral from "c/bandasUmbral";
import { getRecord } from "lightning/uiRecordApi";

function flushPromises() {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deja terminar las promesas pendientes
    setTimeout(resolve, 0);
  });
}

function campo(value) {
  return { value, displayValue: null };
}

describe("c-bandas-umbral", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function elemento(propiedades) {
    const el = createElement("c-bandas-umbral", { is: BandasUmbral });
    Object.assign(el, propiedades);
    document.body.appendChild(el);
    return el;
  }

  function bandas(el) {
    return Array.from(el.shadowRoot.querySelectorAll(".banda")).map(
      (banda) =>
        banda.querySelector(".banda-nombre").textContent.trim() +
        " " +
        banda.querySelector(".banda-rango").textContent.trim()
    );
  }

  it("dibuja las cinco bandas de una medición con sus fronteras", async () => {
    const el = elemento({
      limite: {
        tipoMedicion: "WATER_PRESSURE",
        unidad: "bar",
        decimales: 2,
        criticoBajo: 1.49,
        advertenciaBajo: 2.49,
        advertenciaAlto: 4.01,
        criticoAlto: 5.01
      }
    });
    await flushPromises();

    expect(bandas(el)).toEqual([
      "Crítico hasta 1.49 bar",
      "Advertencia hasta 2.49 bar",
      "Normal más de 2.49 bar y menos de 4.01 bar",
      "Advertencia desde 4.01 bar",
      "Crítico desde 5.01 bar"
    ]);
  });

  it("omite la banda que el umbral no define", async () => {
    const el = elemento({
      limite: {
        tipoMedicion: "WATER_CONSUMPTION",
        unidad: "L/15 min",
        decimales: 0,
        advertenciaAlto: 401,
        criticoAlto: 651
      }
    });
    await flushPromises();

    expect(bandas(el)).toEqual([
      "Normal menos de 401 L/15 min",
      "Advertencia desde 401 L/15 min",
      "Crítico desde 651 L/15 min"
    ]);
  });

  it("en una cámara cuenta minutos sin señal", async () => {
    const el = elemento({
      limite: {
        tipoMedicion: "CAMERA_CONNECTIVITY",
        minutosAdvertencia: 15,
        minutosCritico: 60
      }
    });
    await flushPromises();

    expect(bandas(el)).toEqual([
      "Normal menos de 15 min sin señal",
      "Advertencia desde 15 min",
      "Crítico desde 60 min"
    ]);
  });

  it("en la página del umbral lee el registro", async () => {
    const el = elemento({ recordId: "a05xx0000001" });
    getRecord.emit({
      apiName: "Umbral__c",
      id: "a05xx0000001",
      fields: {
        Tipo_Medicion__c: campo("TEMPERATURE"),
        Unidad__c: campo("CELSIUS"),
        Decimales__c: campo(1),
        Critico_Bajo__c: campo(14.9),
        Advertencia_Bajo__c: campo(17.9),
        Advertencia_Alto__c: campo(30.1),
        Critico_Alto__c: campo(35.1),
        Minutos_Advertencia__c: campo(null),
        Minutos_Critico__c: campo(null)
      }
    });
    await flushPromises();

    expect(el.shadowRoot.textContent).toContain("Cómo clasifica este umbral");
    expect(bandas(el)[0]).toBe("Crítico hasta 14.9 °C");
    expect(bandas(el)).toHaveLength(5);
  });
});
