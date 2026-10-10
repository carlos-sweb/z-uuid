# Resultados de mejora de z-uuid

Medido con Zig 0.17.0 en Linux-7.2.7-200.fc44.x86_64-x86_64-with-glibc2.43, CPU Intel(R) Core(TM) i3-10100F CPU @ 3.60GHz. Tres procesos independientes, 20 muestras pareadas por caso, tres calentamientos y calibración mínima de 100 ms por versión. Las cifras describen esta máquina; aarch64 solo se verificó por compilación.

## Resultado final

| Caso | Viejo ns | Nuevo ns | Aceleración |
|---|---:|---:|---:|
| Comparación v7 | 11.935 | 2.008 | 5.941× |
| Ordenamiento v7 (ns/elemento) | 115.241 | 28.052 | 4.114× |
| Conversión a texto | 11.152 | 6.831 | 1.615× |
| Formato con writer | 18.660 | 12.067 | 1.555× |
| Generador, mismo timestamp / PRNG | 15.201 | 7.468 | 2.035× |
| Generador, timestamp creciente / IoSource | 48.488 | 26.059 | 1.862× |

## Cambios aceptados y descartados

- Aceptados: comparación por dos u64 big-endian, tabla de parejas hexadecimales, flujo simplificado y entropía agrupada al resembra del generador. Siembra de 11 bits con margen mínimo de 2049 emisiones.
- Se conserva el parser: posiciones fijas con switch empeoraron el rendimiento; la tabla de decodificación mejoró texto válido pero penalizó errores tempranos.
- Se conservan solicitudes separadas de v7At: el agrupamiento ayudó a IoSource pero empeoró DefaultPrng.
- v4, eql y version mantienen su implementación; v7 y next comparten la conversión validada del reloj.

En los wrappers uniformes, código más datos de solo lectura pasó de 2662 a 2444 bytes. La tabla de formato ocupa 512 bytes; el total de los wrappers disminuye por las otras optimizaciones. No equivale al tamaño de todos los binarios consumidores.

## Comportamiento y validación

- Ráfaga de 100.000 IDs con reloj fijo: deriva de 45 a 31 ms; resembra de 46 a 32; solicitudes al RNG de 100.046 a 100.000. Fuente Counted(DefaultPrng), semilla 0x1709562.
- 29 tests pasan en Debug, ReleaseSafe y ReleaseFast. Tests completos compilan para aarch64-linux y las autodocs se generan.
- Firmas públicas, formato binario/textual y errores se conservan. Las secuencias generadas con una semilla fija pueden cambiar.

## Variaciones observadas

El conjunto final completo registró una caída cercana al 3,1% en una sesión de v7+texto con PRNG. Tres procesos adicionales midieron aceleraciones de 0,986×, 1,016× y 1,019×: no reprodujeron esa caída y quedaron dentro del margen del 3%. Se conserva la optimización aceptada en las pruebas aisladas, sin atribuir una ganancia estable a ese caso. Las muestras originales siguen disponibles.

El parser sin cambios mostró una variación pequeña en rechazo de guiones inválidos: aproximadamente −1,8% en la mediana de sesiones y una sesión cercana a −3,4%. No se modificó su algoritmo. El informe conserva esos resultados en lugar de presentar una garantía universal de ausencia de regresiones.

## Evidencia

- [Comparación final completa](final-report.md)
- [Alternativas y criterios de selección](candidates-report.md)
- [Repetición de v7+texto](verification-v7-string/final-report.md)
- [Tamaño de código y tablas](sizes.json)
- [Contadores de comportamiento](behavior.jsonl)
- [Fuentes exactas de la ejecución final](snapshots/final/README.md)
- Archivos final-1.jsonl a final-3.jsonl: muestras crudas, medianas e intervalos bootstrap al 95%.
