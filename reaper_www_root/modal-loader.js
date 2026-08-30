// modal-loader.js — carga los fragmentos HTML de cada modal (modals/*/*.html)
// e inyecta su markup dentro de #modalsRoot al boot.
//
// Por qué: cada modal es HTML + JS separados (ver 03_CONVENCIONES / sesión de
// modularización). El JS de cada modal (onclick inline, IDs de sus propios
// elementos) asume que su HTML ya está en el DOM — este loader se encarga de
// ponerlo ahí antes de que el usuario pueda interactuar.
//
// Todo corre en red local (mismo origen que sirve REAPER), así que el fetch
// es prácticamente instantáneo — no hay estado de "cargando" visible.
//
// Los handlers de wwr_onreply que tocan elementos de un modal (por ID) ya
// están guardados con `if (elemento) {...}` en index.html, así que no hay
// riesgo de excepción si un poll llega antes de que termine esta carga.
//
// Para sumar un modal nuevo: agregar su ruta a NIK_MODAL_FRAGMENTS.
var NIK_MODAL_FRAGMENTS = [
    "modals/playrate/playrate.html",
    "modals/reapitch/reapitch.html",
    "modals/tracksvis/tracksvis.html",
    "modals/marker-browser/marker-browser.html",
    "modals/project-tabs/project-tabs.html"
];

(function nikLoadModals() {
    var root = document.getElementById("modalsRoot");
    if (!root) {
        console.error("modal-loader: no se encontró #modalsRoot en el DOM");
        return;
        }
    NIK_MODAL_FRAGMENTS.forEach(function (path) {
        fetch(path)
            .then(function (res) {
                if (!res.ok) throw new Error(path + " -> HTTP " + res.status);
                return res.text();
                })
            .then(function (html) {
                root.insertAdjacentHTML("beforeend", html);
                })
            .catch(function (err) {
                console.error("modal-loader: fallo cargando", path, err);
                });
        });
    })();
