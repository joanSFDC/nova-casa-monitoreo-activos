trigger AvisoDeSenal on Aviso_de_Senal__e (after insert) {
    ProcesamientoServicio.procesar(Trigger.new);
}
