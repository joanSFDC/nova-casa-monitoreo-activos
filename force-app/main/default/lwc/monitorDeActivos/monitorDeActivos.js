import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import LOCALE from "@salesforce/i18n/locale";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import obtenerPanel from "@salesforce/apex/MonitorControlador.obtenerPanel";
import abrirIntervencion from "@salesforce/apex/MonitorControlador.abrirIntervencion";
import NotaIntervencion from "c/notaIntervencion";

const CANAL_AVISO = "/event/Aviso_de_Senal__e";
const ESPERA_MS = 2000;
const VIGILANCIA_MS = 60000;
const POR_BOTON = "boton";
const POR_AVISO = "aviso";
const POR_VIGILANCIA = "vigilancia";

export default class MonitorDeActivos extends NavigationMixin(
  LightningElement
) {
  edificioId = "";
  filtroSeveridad = null;
  error;
  errorEsPermiso = false;
  actualizando = false;
  anuncio = "";
  anunciarCarga = true;
  suscripcion;
  temporizador;
  vigilancia;
  _wire;

  @wire(obtenerPanel, { edificioId: "$edificioId" })
  recibirPanel(resultado) {
    this._wire = resultado;
    if (resultado.data) {
      this.error = undefined;
      this.errorEsPermiso = false;
      if (this.anunciarCarga) {
        this.anunciarCarga = false;
        this.anuncio = this.textoActualizado();
      }
    } else if (resultado.error) {
      this.error = this.textoError(resultado.error);
      this.errorEsPermiso = this.esPermiso(resultado.error);
      this.anuncio = "No se pudo cargar el monitor. " + this.error;
    }
  }

  connectedCallback() {
    this.anuncio = "Cargando el monitor";
    onError(() => {});
    subscribe(CANAL_AVISO, -1, () => {
      this.programarConsulta();
    }).then((respuesta) => {
      this.suscripcion = respuesta;
    });
    this.vigilar();
  }

  disconnectedCallback() {
    if (this.temporizador) {
      clearTimeout(this.temporizador);
    }
    if (this.vigilancia) {
      clearTimeout(this.vigilancia);
      this.vigilancia = undefined;
    }
    if (this.suscripcion) {
      unsubscribe(this.suscripcion);
      this.suscripcion = undefined;
    }
  }

  get panel() {
    return this._wire && this._wire.data ? this._wire.data : null;
  }

  get cargando() {
    return !this.panel && !this.error;
  }

  get filas() {
    return this.panel && this.panel.filas ? this.panel.filas : [];
  }

  get filasVisibles() {
    const base = !this.filtroSeveridad
      ? this.filas
      : this.filas.filter((fila) => fila.severidad === this.filtroSeveridad);
    return base.map((fila) => ({
      ...fila,
      claseSeveridad: this.claseSeveridad(fila.severidad),
      etiquetaAccion: fila.casoId ? "Ver incidente" : "Abrir intervención",
      tituloAccion: fila.casoId
        ? "Abrir el incidente existente"
        : "Abrir una intervención para este equipo"
    }));
  }

  get sinResultadosDeFiltro() {
    return (
      this.filas.length > 0 &&
      this.filasVisibles.length === 0 &&
      this.filtroSeveridad != null
    );
  }

  get opcionesEdificio() {
    const opciones = [{ label: "Todos los edificios", value: "" }];
    if (!this.panel || !this.panel.edificios) {
      return opciones;
    }
    return opciones.concat(
      this.panel.edificios.map((edificio) => ({
        label: edificio.nombre,
        value: edificio.id
      }))
    );
  }

  get mostrarSelectorEdificio() {
    return (
      this.panel && this.panel.edificios && this.panel.edificios.length > 1
    );
  }

  get botonCriticos() {
    return this.claseContador("Critico");
  }

  get botonAdvertencias() {
    return this.claseContador("Advertencia");
  }

  get botonNormales() {
    return this.claseContador("Normal");
  }

  get filtroCritico() {
    return this.filtroSeveridad === "Critico";
  }

  get filtroAdvertencia() {
    return this.filtroSeveridad === "Advertencia";
  }

  get filtroNormal() {
    return this.filtroSeveridad === "Normal";
  }

  get etiquetaCriticos() {
    return this.contar("criticos", "crítico", "críticos");
  }

  get etiquetaAdvertencias() {
    return this.contar("advertencias", "advertencia", "advertencias");
  }

  get etiquetaNormales() {
    return this.contar("normales", "normal", "normales");
  }

  contar(campo, singular, plural) {
    const n = this.panel ? this.panel[campo] : 0;
    return n + " " + (n === 1 ? singular : plural);
  }

  claseContador(severidad) {
    return this.filtroSeveridad === severidad
      ? "slds-button slds-button_brand"
      : "slds-button slds-button_neutral";
  }

  claseSeveridad(severidad) {
    if (severidad === "Critico") {
      return "sev sev_critico";
    }
    if (severidad === "Advertencia") {
      return "sev sev_advertencia";
    }
    return "sev sev_normal";
  }

  textoError(error) {
    if (!error) {
      return "No se pudo cargar el monitor.";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((item) => item.message).join(" ");
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || "No se pudo cargar el monitor.";
  }

  esPermiso(error) {
    const texto = this.textoError(error).toLowerCase();
    return (
      texto.includes("insufficient") ||
      texto.includes("permission") ||
      texto.includes("no such column") ||
      texto.includes("acceso")
    );
  }

  programarConsulta() {
    if (this.temporizador) {
      clearTimeout(this.temporizador);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- una sola consulta por rafaga de avisos
    this.temporizador = setTimeout(() => {
      this.temporizador = undefined;
      this.consultar(POR_AVISO);
    }, ESPERA_MS);
  }

  /**
   * Sin avisos no hay consultas, y el aviso de atraso y las antiguedades solo
   * los recalcula el servidor. Si pasa un minuto sin consultar, se consulta.
   */
  vigilar() {
    if (this.vigilancia) {
      clearTimeout(this.vigilancia);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- la ingesta parada no manda avisos
    this.vigilancia = setTimeout(() => {
      this.vigilancia = undefined;
      this.consultar(POR_VIGILANCIA);
    }, VIGILANCIA_MS);
  }

  consultar(origen) {
    if (!this._wire) {
      this.vigilar();
      return Promise.resolve();
    }
    const enSilencio = origen === POR_VIGILANCIA;
    const atrasadaAntes = this.consultaAtrasada;
    if (!enSilencio) {
      this.actualizando = true;
    }
    if (origen === POR_BOTON) {
      this.anuncio = "Actualizando el monitor";
    }
    return refreshApex(this._wire)
      .then(() => {
        this.error = undefined;
        this.errorEsPermiso = false;
        if (!enSilencio) {
          this.anuncio = this.textoActualizado();
        } else if (this.consultaAtrasada !== atrasadaAntes) {
          this.anuncio = this.consultaAtrasada
            ? "La última consulta al proveedor se atrasó. Los datos pueden no estar al día."
            : "La consulta al proveedor volvió a estar al día.";
        }
      })
      .catch((error) => {
        this.error = this.textoError(error);
        this.errorEsPermiso = this.esPermiso(error);
        this.anuncio = "No se pudo actualizar el monitor. " + this.error;
      })
      .finally(() => {
        this.actualizando = false;
        this.vigilar();
      });
  }

  get consultaAtrasada() {
    return Boolean(this.panel && this.panel.consultaAtrasada);
  }

  textoActualizado() {
    const hora = new Intl.DateTimeFormat(LOCALE, {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: TIME_ZONE
    }).format(new Date());
    return "Monitor actualizado a las " + hora;
  }

  handleEdificio(event) {
    this.edificioId = event.detail.value;
    this.filtroSeveridad = null;
    this.anunciarCarga = true;
    this.anuncio = "Actualizando el monitor";
  }

  handleFiltro(event) {
    const valor = event.currentTarget.dataset.severidad;
    this.filtroSeveridad = this.filtroSeveridad === valor ? null : valor;
  }

  handleActualizar() {
    this.consultar(POR_BOTON);
  }

  handleReintentar() {
    this.error = undefined;
    this.consultar(POR_BOTON);
  }

  handleActivo(event) {
    const id = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName: "Activo__c",
        actionName: "view"
      }
    });
  }

  handleAccion(event) {
    const estadoId = event.currentTarget.dataset.estado;
    const casoId = event.currentTarget.dataset.caso;
    if (casoId) {
      this.irAlCaso(casoId);
      return;
    }
    const fila = this.filas.find((item) => item.estadoId === estadoId);
    NotaIntervencion.open({
      size: "small",
      equipo: fila ? fila.equipo + " · " + fila.medicion : ""
    }).then((respuesta) => {
      if (respuesta) {
        this.abrir(estadoId, respuesta.nota);
      }
    });
  }

  abrir(estadoId, nota) {
    this.actualizando = true;
    abrirIntervencion({ estadoId, nota })
      .then((id) => {
        this.irAlCaso(id);
      })
      .catch((error) => {
        this.error = this.textoError(error);
        this.errorEsPermiso = this.esPermiso(error);
      })
      .finally(() => {
        this.actualizando = false;
      });
  }

  irAlCaso(id) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName: "Case",
        actionName: "view"
      }
    });
  }
}
