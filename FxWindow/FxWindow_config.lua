-- Área cliente de la ventana del FX, en píxeles de pantalla.
-- Se evalúa en orden: gana la primera coincidencia, así que las entradas
-- específicas van antes que las genéricas. `match` es una subcadena del
-- nombre del FX, sin distinguir mayúsculas.
-- view_w / view_h (opcionales): tamaño esperado de la vista del plugin; si
-- están, se verifica además del área cliente.
return {
  { match = "MODO BASS 2", x = 196, y = 67, w = 1531, h = 967, view_w = 1531, view_h = 940 },
  { match = "Ample Guitar L", x = 5, y = 45, w = 1904, h = 1001 },
}