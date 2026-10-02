import { LightningElement, api } from "lwc";

export default class LightningModal extends LightningElement {
  static open = jest.fn();
  @api close = jest.fn();
  @api label;
  @api size;
  @api description;
  @api disableClose;
}
