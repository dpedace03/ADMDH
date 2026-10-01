-- =====================================================================
--  ADMINISTRACIÓN DORMYS — Esquema de base de datos (PostgreSQL / Supabase)
--  Reemplaza los datos que hoy viven en localStorage / IndexedDB.
--  Ejecutar completo en: Supabase > SQL Editor > New query > Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) CONFIGURACIÓN
-- ---------------------------------------------------------------------

-- Ajustes sueltos de la app (textoImporteConfig, appBgColor, appCardBgColor).
-- NO se guarda el githubToken: es un secreto y no debe vivir en la base.
create table if not exists app_config (
    clave       text primary key,
    valor       text not null,
    updated_at  timestamptz not null default now()
);

insert into app_config (clave, valor) values
    ('texto_importe',      'Importe Total: $'),
    ('app_bg_color',       '#f1f5f9'),
    ('app_card_bg_color',  '#ffffff'),
    ('texto_whatsapp_presupuesto',
     'Hola {proveedor}, ¿cómo estás? Te escribimos de Administración Dormys para pedirte un presupuesto del siguiente trabajo:')
on conflict (clave) do nothing;

-- Categorías de tareas (categoriasConfig)
create table if not exists categorias (
    id      bigint generated always as identity primary key,
    nombre  text not null unique,
    color   text not null default '#3b82f6'
);

insert into categorias (nombre, color) values
    ('Mantenimiento', '#3b82f6'),
    ('Jardinería',    '#10b981'),
    ('Electricidad',  '#f59e0b'),
    ('Limpieza',      '#8b5cf6'),
    ('General',       '#64748b')
on conflict (nombre) do nothing;

-- Estados de novedades (estadosConfig)
create table if not exists estados (
    id      bigint generated always as identity primary key,
    nombre  text not null unique,
    color   text not null default '#3b82f6'
);

insert into estados (nombre, color) values
    ('En espera',      '#f59e0b'),
    ('En reparacion',  '#3b82f6'),
    ('Reparado',       '#10b981')
on conflict (nombre) do nothing;

-- Estados de presupuestos (estadosPresupuestoConfig).
-- "Solicitado" lo asigna el botón "Pedir presupuesto" y no debe eliminarse.
create table if not exists estados_presupuesto (
    id      bigint generated always as identity primary key,
    nombre  text not null unique,
    color   text not null default '#3b82f6'
);

insert into estados_presupuesto (nombre, color) values
    ('Solicitado', '#3b82f6'),
    ('Pendiente',  '#f59e0b'),
    ('Aprobado',   '#10b981'),
    ('Rechazado',  '#ef4444')
on conflict (nombre) do nothing;

-- Botones del menú (menuConfig): subnúmero 0 = menú principal; mismo número y subnúmero distinto
-- de 0 = pantalla que se abre al hacer clic en el botón de ese número.
create table if not exists menu_botones (
    id         text primary key,
    texto      text not null,
    numero     integer not null check (numero >= 1),
    subnumero  integer not null default 0 check (subnumero >= 0),
    constraint menu_numero_subnumero_unico unique (numero, subnumero)
);

insert into menu_botones (id, texto, numero, subnumero) values
    ('empleados', 'Empleados', 1, 0), ('casita', 'Casita', 2, 0), ('techos', 'Techos', 3, 0),
    ('presupuestos', 'Presupuestos', 4, 0), ('proveedores', 'Proveedores', 5, 0), ('informes', 'Informes', 6, 0),
    ('gastos', 'Gastos', 7, 0), ('piscina', 'Piscina', 8, 0), ('electrogeno', 'Grupo electrógeno', 9, 0),
    ('matafuegos', 'Matafuegos', 10, 0), ('tareas', 'Tareas', 11, 0), ('herramientas', 'Herramientas', 12, 0),
    ('procedimientos', 'Procedimientos', 13, 0), ('registro', 'Registro', 14, 0),
    ('cronograma', 'Cronograma semanal', 15, 0), ('cronograma-anual', 'Cronograma anual', 16, 0)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2) DORMYS (1 a 99), PROPIETARIOS Y REPARACIONES
-- ---------------------------------------------------------------------

-- dormysData: { 1: {duenio}, ..., 99: {duenio} }
create table if not exists dormys (
    numero  smallint primary key check (numero between 1 and 99),
    duenio  text not null default ''
);

insert into dormys (numero, duenio)
select n, 'Propietario ' || n
from generate_series(1, 99) as n
on conflict (numero) do nothing;

-- reparacionesData: { 1: {estado, presupuesto, orden, fecha}, ... }
create table if not exists reparaciones (
    dormy_numero  smallint primary key references dormys(numero) on delete cascade,
    estado        text not null default 'Sin registrar'
                  check (estado in ('Reparación urgente','Reparación media','Reparación parcial',
                                    'Reparación leve','Reparado','Sin registrar')),
    presupuesto   text not null default '',
    orden         text not null default '',
    fecha         date
);

insert into reparaciones (dormy_numero)
select numero from dormys
on conflict (dormy_numero) do nothing;

-- ---------------------------------------------------------------------
-- 3) MOVIMIENTOS ECONÓMICOS Y NOVEDADES
-- ---------------------------------------------------------------------

-- novedades (techos)
create table if not exists novedades (
    id           bigint generated always as identity primary key,
    dormy_numero smallint references dormys(numero) on delete set null,
    fecha        date,
    estado       text not null default '',
    monto        numeric(14,2) not null default 0,
    descripcion  text not null default '',
    observacion  text not null default '',
    created_at   timestamptz not null default now()
);
create index if not exists idx_novedades_dormy on novedades(dormy_numero);
create index if not exists idx_novedades_fecha on novedades(fecha desc);

-- pagos
create table if not exists pagos (
    id           bigint generated always as identity primary key,
    fecha        date,
    responsable  text not null default '',
    monto        numeric(14,2) not null default 0,
    concepto     text not null default '',
    created_at   timestamptz not null default now()
);
create index if not exists idx_pagos_fecha on pagos(fecha desc);

-- presupuestosData
create table if not exists presupuestos (
    id           bigint generated always as identity primary key,
    fecha        date,
    autor        text not null default '',
    importe      numeric(14,2) not null default 0,
    estado       text not null default '',
    descripcion  text not null default '',
    created_at   timestamptz not null default now()
);
create index if not exists idx_presupuestos_fecha on presupuestos(fecha desc);

-- Adjuntos (hoy en IndexedDB como base64). Los archivos van al bucket
-- "adjuntos" de Supabase Storage; acá solo se guarda la referencia.
create table if not exists adjuntos (
    id             bigint generated always as identity primary key,
    nombre         text not null,
    storage_path   text not null,
    mime_type      text,
    novedad_id     bigint references novedades(id)     on delete cascade,
    pago_id        bigint references pagos(id)         on delete cascade,
    presupuesto_id bigint references presupuestos(id)  on delete cascade,
    created_at     timestamptz not null default now(),
    -- cada adjunto pertenece a exactamente un registro
    constraint adjunto_un_solo_dueno check (
        (novedad_id is not null)::int +
        (pago_id is not null)::int +
        (presupuesto_id is not null)::int = 1
    )
);
create index if not exists idx_adjuntos_novedad     on adjuntos(novedad_id);
create index if not exists idx_adjuntos_pago        on adjuntos(pago_id);
create index if not exists idx_adjuntos_presupuesto on adjuntos(presupuesto_id);

-- ---------------------------------------------------------------------
-- 3b) PROVEEDORES
-- ---------------------------------------------------------------------

-- tareasProveedorConfig: rubros que se cargan en Configuración
create table if not exists tareas_proveedor (
    id      bigint generated always as identity primary key,
    nombre  text not null unique
);

insert into tareas_proveedor (nombre) values
    ('Albañil'), ('Pintura'), ('Jardinería'), ('Techos'), ('Electricidad'), ('Plomería')
on conflict (nombre) do nothing;

-- proveedoresData
create table if not exists proveedores (
    id          bigint generated always as identity primary key,
    nombre      text not null,
    apellido    text not null,
    dni         text not null unique check (dni ~ '^[0-9]{7,8}$'),
    whatsapp    text not null,
    created_at  timestamptz not null default now()
);

-- Tareas que realiza cada proveedor (relación N a N).
-- Si se elimina una tarea del catálogo, se quita de los proveedores.
create table if not exists proveedor_tareas (
    proveedor_id  bigint not null references proveedores(id)       on delete cascade,
    tarea_id      bigint not null references tareas_proveedor(id)  on delete cascade,
    primary key (proveedor_id, tarea_id)
);
create index if not exists idx_proveedor_tareas_tarea on proveedor_tareas(tarea_id);

-- ---------------------------------------------------------------------
-- 4) GRUPO ELECTRÓGENO
-- ---------------------------------------------------------------------

-- electrogenoData: la app maneja un único grupo (fila única, id = 1)
create table if not exists grupo_electrogeno (
    id                 smallint primary key default 1 check (id = 1),
    descripcion        text not null default '',
    service            text not null default '',   -- "¿Cuándo pedir Service?"
    combustible        text not null default '',   -- "¿A quién pedir combustible?"
    horas_ultimo_service numeric(10,1) not null default 0,
    horas_totales      numeric(10,1) not null default 0,
    observacion        text not null default '',
    updated_at         timestamptz not null default now()
);

-- electrogenoNovedades
create table if not exists electrogeno_novedades (
    id           bigint generated always as identity primary key,
    fecha        date,
    importe      numeric(14,2) not null default 0,
    descripcion  text not null default '',
    observacion  text not null default '',
    created_at   timestamptz not null default now()
);
create index if not exists idx_electro_nov_fecha on electrogeno_novedades(fecha desc);

-- ---------------------------------------------------------------------
-- 5) SEGURIDAD, TAREAS Y PERSONAL
-- ---------------------------------------------------------------------

-- matafuegosData
create table if not exists matafuegos (
    id           bigint generated always as identity primary key,
    nro          text not null default '',
    ubicacion    text not null default '',
    vencimiento  date
);
create index if not exists idx_matafuegos_venc on matafuegos(vencimiento);

-- tareasData (catálogo de tareas)
create table if not exists tareas (
    id           bigint generated always as identity primary key,
    nombre       text not null,
    responsable  text not null default '',
    categoria    text not null default '',
    descripcion  text not null default ''
);

-- registrosData (tareas realizadas)
create table if not exists registros (
    id           bigint generated always as identity primary key,
    fecha        date,
    tarea        text not null default '',
    responsable  text not null default '',
    observacion  text not null default ''
);
create index if not exists idx_registros_fecha on registros(fecha desc);

-- herramientasData
create table if not exists herramientas (
    id           bigint generated always as identity primary key,
    nombre       text not null,
    descripcion  text not null default '',
    estado       text not null default 'Activa' check (estado in ('Activa', 'En reparación', 'En desuso')),
    created_at   timestamptz not null default now()
);
create index if not exists idx_herramientas_estado on herramientas(estado);

-- procedimientosData
create table if not exists procedimientos (
    id           bigint generated always as identity primary key,
    nombre       text not null,
    categoria    text not null default '',
    responsable  text not null default '',
    descripcion  text not null,
    created_at   timestamptz not null default now()
);
create index if not exists idx_procedimientos_categoria on procedimientos(categoria);

-- cronogramaData (agenda semanal)
create table if not exists cronograma (
    id           bigint generated always as identity primary key,
    dia          text not null default '',
    horario      text not null default '',
    tarea        text not null default '',
    responsable  text not null default '',
    observacion  text not null default ''
);

-- cronogramaAnualData: un texto por mes de cada año ({"2026-09": "texto"})
create table if not exists cronograma_anual (
    anio        smallint not null check (anio between 2000 and 2100),
    mes         smallint not null check (mes between 1 and 12),
    texto       text not null default '',
    updated_at  timestamptz not null default now(),
    primary key (anio, mes)
);

-- ---------------------------------------------------------------------
-- 5b) EMPLEADO (Facundo): facundoData
-- ---------------------------------------------------------------------

-- Ficha (fila única, id = 1)
create table if not exists empleado_ficha (
    id                smallint primary key default 1 check (id = 1),
    nombre            text not null default '',
    apellido          text not null default '',
    dni               text not null default '' check (dni = '' or dni ~ '^[0-9]{7,8}$'),
    fecha_nacimiento  date,
    domicilio         text not null default '',
    whatsapp          text not null default '',
    puesto            text not null default '',
    puesto_descripcion text not null default '',   -- descripción detallada del puesto
    updated_at        timestamptz not null default now()
);

-- Jornada laboral por temporada (Invierno / Verano)
create table if not exists empleado_horarios (
    temporada    text primary key check (temporada in ('invierno', 'verano')),
    hora_inicio  time,
    hora_fin     time
);
insert into empleado_horarios (temporada) values ('invierno'), ('verano')
on conflict (temporada) do nothing;

-- Vacaciones
create table if not exists empleado_vacaciones (
    id            bigint generated always as identity primary key,
    anio          smallint check (anio between 2000 and 2100),
    fecha_inicio  date not null,
    fecha_fin     date not null,
    dias_totales  smallint check (dias_totales >= 0),
    dias_tomados  smallint check (dias_tomados >= 0),
    constraint vacaciones_fechas_ok check (fecha_fin >= fecha_inicio),
    constraint vacaciones_dias_ok   check (dias_tomados is null or dias_totales is null or dias_tomados <= dias_totales)
);
create index if not exists idx_empleado_vac_anio on empleado_vacaciones(anio);

-- Registro de tareas del empleado
create table if not exists empleado_tareas (
    id           bigint generated always as identity primary key,
    fecha        date not null,
    tarea        text not null,
    observacion  text not null default '',
    created_at   timestamptz not null default now()
);
create index if not exists idx_empleado_tareas_fecha on empleado_tareas(fecha desc);

-- ---------------------------------------------------------------------
-- 6) STORAGE PARA ARCHIVOS ADJUNTOS
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('adjuntos', 'adjuntos', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 7) SEGURIDAD (Row Level Security)
-- ---------------------------------------------------------------------
-- ATENCIÓN: la app actual no tiene login. Estas políticas dejan leer y
-- escribir a cualquiera que tenga la clave "anon" del proyecto (que queda
-- visible en el HTML publicado). Sirve para arrancar, pero si la app es
-- pública conviene sumar Supabase Auth y cambiar "anon" por "authenticated".
do $$
declare
    t text;
begin
    foreach t in array array[
        'app_config','categorias','estados','estados_presupuesto','menu_botones','dormys','reparaciones','novedades',
        'pagos','presupuestos','adjuntos','grupo_electrogeno',
        'electrogeno_novedades','matafuegos','tareas','registros',
        'herramientas','procedimientos','cronograma','cronograma_anual','empleado_ficha','empleado_horarios',
        'empleado_vacaciones','empleado_tareas','tareas_proveedor','proveedores','proveedor_tareas'
    ]
    loop
        execute format('alter table %I enable row level security', t);
        execute format('drop policy if exists acceso_app on %I', t);
        execute format(
            'create policy acceso_app on %I for all to anon, authenticated using (true) with check (true)', t);
    end loop;
end $$;

drop policy if exists acceso_app_storage on storage.objects;
create policy acceso_app_storage on storage.objects
    for all to anon, authenticated
    using (bucket_id = 'adjuntos')
    with check (bucket_id = 'adjuntos');
