// Crea o actualiza los seis usuarios de la demostracion, les asigna conjuntos
// de permisos y los mete en los grupos publicos de cada ciudad.
//
// Uso, desde la raiz del repositorio:
//   sf apex run -f scripts/apex/crear-usuarios-demo.apex
//   ./scripts/crear-usuarios-demo.sh
//
// Es idempotente: si el Username ya existe, no duplica. Las asignaciones se
// saltan si ya estan. No guarda contrasenas. A los humanos les manda el
// correo de restablecer clave; al usuario de integracion no.
//
// El correo de los humanos apunta a Juan para que llegue la invitacion.
// El Username es lo que se escribe en el login.

String correoHumano = 'juan.palma.a0651088b6@salesforce.com';

Profile perfilMinimo = [
    SELECT Id
    FROM Profile
    WHERE Name = 'Minimum Access - Salesforce'
    LIMIT 1
];
Profile perfilApi = [
    SELECT Id
    FROM Profile
    WHERE Name = 'Salesforce API Only System Integrations'
    LIMIT 1
];

Map<String, PermissionSet> conjuntos = new Map<String, PermissionSet>();
for (PermissionSet ps : [
    SELECT Id, Name
    FROM PermissionSet
    WHERE Name IN (
        'Nova_Casa_Operador',
        'Nova_Casa_Coordinador',
        'Nova_Casa_Gerencia',
        'Nova_Casa_Administracion',
        'Nova_Casa_Integracion'
    )
]) {
    conjuntos.put(ps.Name, ps);
}

Map<String, Group> grupos = new Map<String, Group>();
for (Group g : [
    SELECT Id, DeveloperName
    FROM Group
    WHERE DeveloperName IN ('Operadores_Bogota', 'Operadores_Barranquilla')
]) {
    grupos.put(g.DeveloperName, g);
}

PermissionSetLicense licenciaApi = [
    SELECT Id
    FROM PermissionSetLicense
    WHERE DeveloperName = 'SalesforceAPIIntegrationPsl'
    LIMIT 1
];

// username, first, last, alias, nickname, title, profile, permset, groups csv, esHumano
List<String> filas = new List<String>{
    'operador.bogota.novacasa.95b2e3a11aa777@salesforce.com|Operador|Bogotá|opbog|op-bogota|Operador de edificios|minimo|Nova_Casa_Operador|Operadores_Bogota|humano',
    'operador.baq.novacasa.95b2e3a11aa777@salesforce.com|Operador|Barranquilla|opbaq|op-barranquilla|Operador de edificios|minimo|Nova_Casa_Operador|Operadores_Barranquilla|humano',
    'coordinador.novacasa.95b2e3a11aa777@salesforce.com|Coordinador|Mantenimiento|coordmt|coord-mto|Coordinador de mantenimiento|minimo|Nova_Casa_Coordinador|Operadores_Bogota,Operadores_Barranquilla|humano',
    'gerente.novacasa.95b2e3a11aa777@salesforce.com|Gerente|Regional|gerreg|gerente-reg|Gerente regional|minimo|Nova_Casa_Gerencia|Operadores_Bogota,Operadores_Barranquilla|humano',
    'admin.novacasa.95b2e3a11aa777@salesforce.com|Administrador|Plataforma|admplat|admin-plat|Administrador de la plataforma|minimo|Nova_Casa_Administracion||humano',
    'integracion.novacasa.95b2e3a11aa777@salesforce.com|Usuario|Integración|integnc|usr-integracion|Usuario de integración|api|Nova_Casa_Integracion||sistema'
};

Set<String> usernames = new Set<String>();
for (String fila : filas) {
    usernames.add(fila.split('\\|')[0]);
}

Map<String, User> existentes = new Map<String, User>();
for (User u : [
    SELECT Id, Username, IsActive
    FROM User
    WHERE Username IN :usernames
]) {
    existentes.put(u.Username, u);
}

List<User> paraInsertar = new List<User>();
List<User> paraActivar = new List<User>();

for (String fila : filas) {
    List<String> c = fila.split('\\|');
    String username = c[0];
    String firstName = c[1];
    String lastName = c[2];
    String alias = c[3];
    String nick = c[4];
    String title = c[5];
    String tipoPerfil = c[6];
    Boolean esHumano = c[9] == 'humano';

    if (existentes.containsKey(username)) {
        User ya = existentes.get(username);
        if (!ya.IsActive) {
            ya.IsActive = true;
            paraActivar.add(ya);
        }
        continue;
    }

    User u = new User();
    u.FirstName = firstName;
    u.LastName = lastName;
    u.Username = username;
    u.Email = esHumano ? correoHumano : username;
    u.Alias = alias;
    u.CommunityNickname = nick;
    u.Title = title;
    u.TimeZoneSidKey = 'America/Bogota';
    u.LocaleSidKey = 'es_CO';
    u.EmailEncodingKey = 'UTF-8';
    u.LanguageLocaleKey = 'es';
    u.ProfileId = tipoPerfil == 'api' ? perfilApi.Id : perfilMinimo.Id;
    u.IsActive = true;
    paraInsertar.add(u);
}

if (!paraInsertar.isEmpty()) {
    insert paraInsertar;
    for (User u : paraInsertar) {
        existentes.put(u.Username, u);
    }
}
if (!paraActivar.isEmpty()) {
    update paraActivar;
}

Set<Id> userIds = new Set<Id>();
for (User u : existentes.values()) {
    userIds.add(u.Id);
}

Set<String> asignacionesHechas = new Set<String>();
for (PermissionSetAssignment psa : [
    SELECT AssigneeId, PermissionSet.Name
    FROM PermissionSetAssignment
    WHERE AssigneeId IN :userIds
]) {
    asignacionesHechas.add(String.valueOf(psa.AssigneeId) + ':' + psa.PermissionSet.Name);
}

Set<String> gruposHechos = new Set<String>();
for (GroupMember gm : [
    SELECT UserOrGroupId, Group.DeveloperName
    FROM GroupMember
    WHERE UserOrGroupId IN :userIds
]) {
    gruposHechos.add(String.valueOf(gm.UserOrGroupId) + ':' + gm.Group.DeveloperName);
}

Set<Id> licenciasHechas = new Set<Id>();
for (PermissionSetLicenseAssign psla : [
    SELECT AssigneeId
    FROM PermissionSetLicenseAssign
    WHERE AssigneeId IN :userIds
      AND PermissionSetLicenseId = :licenciaApi.Id
]) {
    licenciasHechas.add(psla.AssigneeId);
}

List<PermissionSetAssignment> nuevasAsignaciones = new List<PermissionSetAssignment>();
List<GroupMember> nuevosMiembros = new List<GroupMember>();
List<PermissionSetLicenseAssign> nuevasLicencias = new List<PermissionSetLicenseAssign>();
List<Id> humanosParaClave = new List<Id>();

for (String fila : filas) {
    List<String> c = fila.split('\\|');
    String username = c[0];
    String permsetName = c[7];
    String gruposCsv = c[8];
    Boolean esHumano = c[9] == 'humano';
    User u = existentes.get(username);
    String claveAsig = String.valueOf(u.Id) + ':' + permsetName;

    if (!asignacionesHechas.contains(claveAsig) && conjuntos.containsKey(permsetName)) {
        nuevasAsignaciones.add(new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = conjuntos.get(permsetName).Id
        ));
    }

    if (String.isNotBlank(gruposCsv)) {
        for (String nombreGrupo : gruposCsv.split(',')) {
            String claveGrupo = String.valueOf(u.Id) + ':' + nombreGrupo;
            if (!gruposHechos.contains(claveGrupo) && grupos.containsKey(nombreGrupo)) {
                nuevosMiembros.add(new GroupMember(
                    GroupId = grupos.get(nombreGrupo).Id,
                    UserOrGroupId = u.Id
                ));
            }
        }
    }

    if (!esHumano && !licenciasHechas.contains(u.Id)) {
        nuevasLicencias.add(new PermissionSetLicenseAssign(
            AssigneeId = u.Id,
            PermissionSetLicenseId = licenciaApi.Id
        ));
    }

    if (esHumano) {
        humanosParaClave.add(u.Id);
    }
}

if (!nuevasLicencias.isEmpty()) {
    insert nuevasLicencias;
}
if (!nuevasAsignaciones.isEmpty()) {
    insert nuevasAsignaciones;
}
if (!nuevosMiembros.isEmpty()) {
    insert nuevosMiembros;
}

Integer clavesEnviadas = 0;
for (Id humanoId : humanosParaClave) {
    try {
        System.resetPassword(humanoId, true);
        clavesEnviadas++;
    } catch (Exception e) {
        System.debug('No se pudo enviar clave a ' + humanoId + ': ' + e.getMessage());
    }
}

System.debug('USUARIOS_DEMO existentes=' + existentes.size()
    + ' insertados=' + paraInsertar.size()
    + ' asignaciones=' + nuevasAsignaciones.size()
    + ' grupos=' + nuevosMiembros.size()
    + ' claves=' + clavesEnviadas);
