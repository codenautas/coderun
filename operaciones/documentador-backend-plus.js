function cambioParametro(variableName, value) {
    if (variableName) {
        var spanElements = document.querySelectorAll("span[bp-variable='" + variableName + "']");
        spanElements.forEach(function (span) {
            span.textContent = value;
        });
    }
}

function parametroOnBlur(event) {
    var input = event.target;
    var value = input.value;
    var variableName = input.getAttribute("bp-parametro");
    cambioParametro(variableName, value);
}

window.onload = function () {
    /** @type {Record<string, {}>} */
    var parametros = {}
    /** @type {NodeListOf<HTMLElement>} */
    var paramElements = document.querySelectorAll("[bp-parametro]")
    paramElements.forEach(function (element) {
        var parametro = element.getAttribute("bp-parametro");
        if (parametro) {
            parametros[parametro] = {};
            element.onblur = parametroOnBlur;
        }
    })
    var codeElements = document.querySelectorAll("pre")
    codeElements.forEach(function (element) {
        var code = element.innerText.split(/(\$(?:\{\w+\}|\w+))/).map(function (part, i) {
            if (i % 2 === 0) {
                return document.createTextNode(part); // Texto normal
            } else {
                var span = document.createElement("span");
                var variable = part.replace(/^\$\{?|\}?$/g, "");
                span.setAttribute("bp-variable", variable);
                span.setAttribute("bp-es", parametros[variable] ? "parametro" : "variable");
                span.textContent = part;
                return span;
            }
        });
        element.innerHTML = "";
        element.append(...code);
    });
    setInterval(() => cambioParametro("ultimos_minutos", new Date(new Date().getTime() - 300000 - new Date().getTimezoneOffset()*60000).toISOString().replace(/T|\..*$/g," ").trim()), 1000)
};
