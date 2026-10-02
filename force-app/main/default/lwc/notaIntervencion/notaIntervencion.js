import { api } from "lwc";
import LightningModal from "lightning/modal";

export default class NotaIntervencion extends LightningModal {
  @api equipo;
  nota = "";

  handleNota(event) {
    this.nota = event.detail.value;
  }

  handleCancelar() {
    this.close();
  }

  handleAbrir() {
    const nota = (this.nota || "").trim();
    this.close({ nota: nota || null });
  }
}
