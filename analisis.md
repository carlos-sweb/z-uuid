# Análisis de z-uuid

Fecha: 2026-09-29  
Alcance: `src/`, `tests/`, `build.zig`, `build.zig.zon`, `README.md`, `plan.md`  
Compilador verificado: Zig 0.16.0  
Tests: `zig build test` pasa (6 tests en `tests/uuid_test.zig`)

`z-uuid` es una librería mínima de UUID v4 y v7 según RFC 9562. El núcleo cabe en un `struct` de 16 bytes, no reserva heap y encaja con el modelo de I/O de Zig 0.16 (`std.Io` + `std.Random` inyectado). El diseño es sólido para el alcance actual. Los riesgos reales están en panics por `@intCast`, en la monotonía de v7 y en API/tests que el RFC y el ecosistema Zig esperan.

---

## 1. Arquitectura

```
src/zuuid.zig     raíz del módulo (reexporta Uuid)
src/uuid.zig      implementación
tests/uuid_test.zig
build.zig         módulo + step `test` (también es el default)
```

`Uuid` guarda el layout big-endian del RFC: nibble de versión en `bytes[6]`, bits de variante `10` en `bytes[8]`. Las operaciones públicas son `v4`, `v7`, `v7At`, `parse`, `toString`, `format`, `version` y `eql`.

Puntos fuertes del diseño:

- El llamador aporta `std.Random`. No hay CSPRNG global oculto. Eso permite tests deterministas con `DefaultPrng` y producción con `std.Random.IoSource`.
- `v7` toma `std.Io` solo para el reloj; `v7At` permite un timestamp explícito. Encaja con Zig 0.16, donde desaparecieron `std.crypto.random` y `std.time.milliTimestamp`.
- `toString` escribe en un buffer del llamador (`*[36]u8`) y `format` usa la firma 0.16 `format(self, w: *std.Io.Writer) std.Io.Writer.Error!void`.
- `build.zig.zon` ya tiene `.name = .zuuid` (enum literal), `.fingerprint` y `.minimum_zig_version = "0.16.0"`.

---

## 2. Memoria y fugas

La librería **no asigna en el heap**. Todo vive en el stack:

| Sitio | Qué reserva | Quién libera |
|---|---|---|
| `v4` / `v7` / `v7At` / `parse` | `[16]u8` local | sale con el `Uuid` por valor |
| `toString` | escribe en `buf` del llamador | el llamador |
| `format` | `[36]u8` local | fin de la función |
| tests | `[200]Uuid` y buffers `[36]u8` | fin del test |

No hay `allocator.create`, `ArrayList`, `dupe`, arenas ni I/O que retenga buffers. **No hay vector de fuga en el código actual.** Un `GeneralPurposeAllocator` con `defer expect(gpa.deinit() == .ok)` no encontraría nada que reclamar.

Riesgos de por vida / aliasing (no son fugas, sí son UAF si el usuario se equivoca):

1. **`std.Random.IoSource` guarda un puntero a sí mismo.** El ejemplo del README es correcto mientras `io_source` viva más que `random`. Este patrón es peligroso:

   ```zig
   fn getRandom(io: std.Io) std.Random {
       const io_source: std.Random.IoSource = .{ .io = io };
       return io_source.interface(); // puntero a io_source, ya muerto al retornar
   }
   ```

   Conviene documentar en el README que `IoSource` tiene que permanecer vivo mientras se use el `Random`.

2. **`bytes` es un campo público mutable.** Un llamador puede corromper versión/variante sin pasar por los constructores. Eso no filtra memoria; sí rompe el invariante que el comentario de `Uuid` afirma (“always the version / always the variant”). `parse` además acepta cualquier hex válido, así que un UUID parseado puede tener versión 0 y variante distinta de `10`.

Recomendación preventiva (para cuando crezca la API):

- Seguir sin asignar. Si se añade parseo URN, compacto o JSON, reutilizar buffers fijos o `std.Io.Writer.fixed`.
- Si se añade un generador v7 monotónico con estado, guardar el contador en un `struct` del llamador (`var gen: Uuid.V7Gen = .{}`) y no en un global. Un global implicaría mutex/`Io.Mutex` y, en forks, reseed del CSPRNG (RFC 9562 §6.9).
- Si algún test futuro asigna, usar `std.testing.allocator` (o GPA en Debug) y comprobar `deinit() == .ok`.

---

## 3. Código muerto y tests que no corren

No hay funciones privadas huérfanas en `uuid.zig`. `hex_chars` y `hexValue` se usan.

Sí hay artefactos y superficie sin ejercicio:

| Ítem | Estado | Acción |
|---|---|---|
| `plan.md` | Un URL a `r4gus/uuid-zig`. No entra en `.paths` del paquete ni en el build | Eliminarlo o convertirlo en nota de diseño |
| `test { _ = @import("uuid.zig"); }` en `src/zuuid.zig` | Nunca se ejecuta: `build.zig` solo testa `tests/uuid_test.zig` | Añadir un `addTest` del módulo raíz, o borrar el bloque |
| `Uuid.v7(random, io)` | API pública, cero tests | Cubrir con `std.testing.io` |
| `Uuid.format` | API pública (`{f}`), cero tests | Cubrir con `std.Io.Writer.fixed` |
| `parse` en mayúsculas | Documentado, cero tests | Añadir un vector `3F2504E0-...` |
| Vectores RFC 9562 Appendix A | Ausentes | Añadir al menos el v7 `017F22E2-79B0-7CC3-98C4-DC0C0C07398F` |

`tests/` está fuera de `.paths` en `build.zig.zon`. Eso es correcto: el tarball del paquete no necesita los tests.

---

## 4. Bugs y riesgos de corrección

### 4.1 `@intCast` de `i64` → `u48` en `v7At` (panic)

```zig
const ts: u48 = @intCast(unix_ms);
```

El campo `unix_ts_ms` del RFC es unsigned 48-bit. El rango legal es `[0, 2^48-1]` (hasta ~año 10889). En Debug/ReleaseSafe:

- `unix_ms < 0` (reloj anterior a 1970) → panic
- `unix_ms > 281_474_976_710_655` → panic

En ReleaseFast/ReleaseSmall el cast overflow es undefined behavior según el modo de overflow del compilador. `v7` hereda el problema: `Clock.real.now` devuelve `Io.Timestamp` con `nanoseconds: i96`, que puede ser negativo.

Propuesta:

```zig
pub fn v7At(random: std.Random, unix_ms: i64) error{InvalidTimestamp}!Uuid {
    const ts = std.math.cast(u48, unix_ms) orelse return error.InvalidTimestamp;
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u48, bytes[0..6], ts, .big);
    // ...
}
```

Cambiar el tipo de retorno es un breaking change (hoy `v7`/`v7At` no fallan). Alternativa no-breaking: saturar con `std.math.lossyCast(u48, @max(unix_ms, 0))` y documentarlo. Para una librería de IDs, el error explícito es más honesto.

### 4.2 v7 no es monotónico dentro del mismo milisegundo

RFC 9562 §6.2 recomienda (SHOULD) un contador en `rand_a` (12 bits) y, si hace falta, en los bits altos de `rand_b`. Hoy cada `v7`/`v7At` rellena 74 bits al azar. Dos UUID generados en el mismo ms pueden ordenarse al revés, que es justo lo que se busca evitar al usar v7 como clave de índice.

Consecuencia práctica: “time-ordered” solo se cumple entre milisegundos distintos. Bajo ráfaga (inserts, logs, jobs) el beneficio de localidad en B-trees se degrada.

Propuesta mínima (Method 1, 12 bits):

```zig
pub const V7Generator = struct {
    last_ms: u48 = 0,
    seq: u12 = 0,

    pub fn next(self: *V7Generator, random: std.Random, unix_ms: u48) Uuid {
        if (unix_ms > self.last_ms) {
            self.last_ms = unix_ms;
            self.seq = @truncate(random.int(u16)); // reseed
        } else {
            self.seq +%= 1; // wrap documentado; o bloquear/avanzar ms
        }
        // escribir unix_ms, version, seq en rand_a, random en rand_b
    }
};
```

Mantener `v7At` puro (sin estado) para tests, y ofrecer el generador con estado para producción. El estado vive en el llamador: cero globales, cero fugas.

### 4.3 Invariante del comentario vs `parse`

El comentario de `Uuid` afirma que versión y variante siempre están sellados, “regardless of which constructor produced it”. `parse` copia hex crudo. O se sella en `parse`, o se relaja el comentario y se añade `variant()`.

### 4.4 Escritura manual del timestamp

Los seis shifts de `v7At` son correctos y equivalen a `std.mem.writeInt(u48, bytes[0..6], ts, .big)`. La forma de `std.mem` deja el endian explícito y elimina una clase de error al copiar el patrón.

---

## 5. Buenas prácticas Zig 0.16

### Lo que ya está bien

- Firma de `format` alineada con `std.Io.Writer` (el `{f}` del README es el correcto en 0.16).
- Reloj vía `std.Io.Clock.real.now(io)`; RNG vía `std.Random`.
- `build.zig.zon` con `fingerprint` y nombre como enum literal.
- API sin alloc; el llamador posee los buffers.
- Tests en archivo aparte, importando el módulo como lo haría un consumidor (`@import("zuuid")`).
- `eql` con `std.mem.eql` sobre 16 bytes: claro y suficiente.

### Ajustes idiomáticos

**1. `writeInt` / `readInt` en lugar de shifts.** El test ya usa `std.mem.readInt(u48, u.bytes[0..6], .big)` para extraer el timestamp. El productor debería usar el inverso.

**2. Comparación y orden.** Para un ID de 16 bytes, comparar como entero big-endian da orden lexicográfico = orden de bytes RFC, que para v7 es orden temporal:

```zig
pub fn order(a: Uuid, b: Uuid) std.math.Order {
    return std.mem.order(u8, &a.bytes, &b.bytes);
}
```

`eql` puede quedarse en `std.mem.eql`. Evitar `@as(u128, @bitCast(bytes))` para ordenar: el `bitCast` sigue el endian nativo y en little-endian el orden numérico no coincide con el del RFC.

**3. Test de `format` con writer fijo (API 0.16):**

```zig
test "format writes the dashed form" {
    const u = try Uuid.parse("3f2504e0-4f89-41d3-9a0c-0305e82c3301");
    var buf: [36]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try u.format(&w);
    try testing.expectEqualStrings("3f2504e0-4f89-41d3-9a0c-0305e82c3301", buf[0..36]);
}
```

**4. Test de `v7` con `std.testing.io`:**

```zig
test "v7 stamps version 7 from the wall clock" {
    var prng = std.Random.DefaultPrng.init(1);
    const u = Uuid.v7(prng.random(), std.testing.io);
    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
}
```

**5. `build.zig`: testear también el módulo raíz** para que el `test { _ = @import("uuid.zig"); }` (y futuros tests embebidos) corran. Propagar `target`/`optimize` al módulo es opcional en un paquete; el consumidor los fija. Sí vale la pena un step `test` que dependa de ambos artefactos.

**6. `expectEqual` sin `@as` intermedios cuando el tipo se infiere**, o al revés: `try testing.expectEqual(4, u.version())` si la sobrecarga lo permite. Menor; consistencia.

**7. Lifetime de `IoSource`.** `interface()` hace `@constCast` y guarda `ptr`. El README debería decir que la fuente vive en el stack del llamador y no se debe devolver el `Random` solo.

**8. No introducir `@cImport`, `std.crypto.random`, `std.time.milliTimestamp`, `ArrayList.init` ni `Thread.Pool`.** El código actual ya los evita. Mantenerlo así en contribuciones.

**9. Campo `bytes`.** En Zig es idiomático dejar los datos públicos. Si se quiere preservar el invariante, un getter `pub fn asBytes(self: Uuid) *const [16]u8` y constructores `fromBytes` que sellen versión/variante (o que documenten que no sellan) dejan la mutación accidental más difícil.

---

## 6. Completeness RFC 9562 (huecos de API)

El README declara alcance v4 + v7. Eso es coherente. Huecos que merecen una decisión explícita, no necesariamente implementación inmediata:

| RFC | Qué falta | Prioridad |
|---|---|---|
| §5.7 / §6.2 | Contador monotónico v7 | Alta (promesa “time-ordered”) |
| §4.1 | `variant()` | Baja |
| §5.9 / §5.10 | `nil` y `max` | Baja, 2 constantes |
| §5.3 / §5.5 | v3/v5 (MD5/SHA-1 + namespace) | Roadmap (`z-crypto`) |
| Appendix A | Vectores de test oficiales | Alta (baratos) |
| §6.9 | Documentar que el CSPRNG lo pone el llamador | Ya está; reforzar el lifetime de `IoSource` |

Parsear solo la forma `8-4-4-4-12` está documentado como decisión. URN (`urn:uuid:…`), llaves `{}` y hex compacto de 32 caracteres pueden esperar.

`order` / `lessThan` sí aportan al caso de uso “v7 como PK”: sin ellos el consumidor reimplementa la comparación de bytes.

---

## 7. Build, empaquetado y docs

- `b.default_step = test_step` es razonable para una librería.
- Falta LICENSE. El paquete se consume por path; sin licencia el reuso legal queda ambiguo.
- El README usa `std.process.Init` (Juicy Main) y `{f}`: correcto para 0.16.
- `plan.md` no aporta al usuario del paquete.
- No hay CI (`.github/workflows` u otro). Un workflow `zig build test` en 0.16.0 evitaría regresiones silenciosas.
- `build.zig.zon` `.paths` omite `tests/` y `plan.md`: correcto para el tarball.

---

## 8. Plan de mejoras (ordenado)

### P0 — Correctitud / no panic

1. Validar `unix_ms` en `v7At` con `std.math.cast(u48, …)` (error o saturación documentada).
2. Reescribir el timestamp con `std.mem.writeInt(u48, …, .big)`.
3. Ajustar el comentario de `Uuid` para `parse`, o sellar versión/variante ahí.

### P1 — Código muerto y cobertura

4. Borrar o reubicar `plan.md`.
5. Hacer correr los tests del módulo raíz, o quitar el bloque `test { _ = @import(...) }`.
6. Tests para `v7` (`std.testing.io`), `format` (`Writer.fixed`), parse mayúsculas y un vector RFC.

### P2 — Promesa time-ordered

7. `V7Generator` con contador `rand_a` (RFC §6.2 Method 1), estado en el llamador.
8. `Uuid.order` para ordenar v7 como el RFC.

### P3 — API y empaque

9. Constantes `nil` / `max`, `variant()`, `fromBytes`.
10. Nota de lifetime de `IoSource` en el README.
11. LICENSE + CI `zig build test`.

Nada de esto introduce heap si se implementa con buffers fijos y structs de estado del llamador.

---

## 9. Resumen

`z-uuid` es una base limpia de Zig 0.16: cero alloc, RNG y reloj inyectados, layout RFC correcto, `format`/`toString` sin heap. No hay fugas de memoria en el código actual. El trabajo útil está en tres frentes:

1. **Sustituir `@intCast` de timestamps por un cast comprobado**, para que un reloj pre-epoch no tire el proceso.
2. **Quitar muertos** (`plan.md`, test del módulo que no se ejecuta) y **cubrir `v7` y `format`**.
3. **Honrar el “time-ordered” de v7** con un generador con contador, estado poseído por el llamador.

Mientras la librería siga sin allocator, el riesgo de leak permanece en cero; el riesgo real es panic por overflow y UUID v7 que no ordenan bajo carga.
`}
