/** @type {Record<string, {}>} */
var parametros = {}
/** @type {Record<string,{}>} */
var valores = {}
/** @type {Array<{fun: Function, element: HTMLElement}>} */
var condiciones = []

function controlCondiciones() {
    condiciones.forEach(function (condicion) {
        var resultado = condicion.fun(valores);
        condicion.element.style.display = resultado ? "" : "none";
        /** @type {HTMLElement|Element} */
        var siguiente = condicion.element.nextElementSibling;
        if (siguiente != null && siguiente?.hasAttribute("bp-sino")) {
            // @ts-expect-error No sabe que nextElementSibling puede ser un HtmlElement
            siguiente.style.display = resultado ? "none" : "";
        }
    });
}

function cambioParametro(variableName, value) {
    if (variableName) {
        valores[variableName] = value;
        var spanElements = document.querySelectorAll("span[bp-variable='" + variableName + "']");
        spanElements.forEach(function (span) {
            span.textContent = value == null ? span.getAttribute('bp-original-value') : value;
        });
        controlCondiciones();
    }
}

function tomarValorDelInput(input) {
    if (input.disalbed) {
        
    }
    var value = input.disabled ? null : input.type == "checkbox" ? input.checked : (input.value || null)
    var variableName = input.getAttribute("bp-parametro");
    cambioParametro(variableName, value);
    if (input.type == "checkbox" && input.nextElementSibling.getAttribute('bp-parametro')) {
        input.nextElementSibling.disabled = !input.checked
        if (input.checked) {
            tomarValorDelInput(input.nextElementSibling)
        } else {
            var variableAsociada = input.nextElementSibling.getAttribute('bp-parametro')
            cambioParametro(variableAsociada, input.hasAttribute("bp-unchecked-value") ? input.getAttribute("bp-unchecked-value") : null );
        }
    }
}

function parametroOnChange(event) {
    /** @type {HTMLInputElement} */
    var input = event.target;
    tomarValorDelInput(input);
}

/** @param {HTMLElement|Text} element */
function interpolarParametros(element){
    if (element instanceof Text) {
        var newNodes = element.textContent.split(/(\$(?:\{\w+\}|\w+))/).map(function (part, i) {
            if (i % 2 === 0) {
                return document.createTextNode(part); // Texto normal
            } else {
                var span = document.createElement("span");
                var variable = part.replace(/^\$\{?|\}?$/g, "");
                span.setAttribute("bp-variable", variable);
                span.setAttribute("bp-es", parametros[variable] ? "parametro" : "variable");
                span.setAttribute("bp-original-value", part);
                span.textContent = part;
                return span;
            }
        });
        return newNodes;
    } else {
        var code = []
        element.childNodes.forEach( 
            /** @param {HTMLElement|Text} e */
            function(e) {
                code.push(...interpolarParametros(e));
            }
        );
        element.innerHTML = "";
        element.append(...code);
        return [element];
    }
}

window.onload = function () {
    /** @type {NodeListOf<HTMLElement>} */
    var paramElements = document.querySelectorAll("[bp-parametro]")
    paramElements.forEach(function (element) {
        var parametro = element.getAttribute("bp-parametro");
        if (parametro) {
            parametros[parametro] = {};
            // @ts-expect-error cualquiera podría ser el elemento y podría no tener type (no me jode)
            if (element.type == "checkbox") {
                element.onchange = parametroOnChange;
            } else {
                element.oninput = parametroOnChange;
            }
        }
    })
    var codeElements = document.querySelectorAll("pre")
    codeElements.forEach(interpolarParametros)
    /** @type {NodeListOf<HTMLElement>} */
    var soloSiElements = document.querySelectorAll("[bp-solo-si]");
    soloSiElements.forEach(function (element) {
        var condition = element.getAttribute("bp-solo-si");
        if (condition) {
            var fun = new Function("valores", "return " + condition.replace(/(\w+)/g, "valores.$1"))
            condiciones.push({fun, element});
        }
    })
    setInterval(() => cambioParametro("ultimos_minutos", new Date(new Date().getTime() - 300000 - new Date().getTimezoneOffset()*60000).toISOString().replace(/T|\..*$/g," ").trim()), 1000)
    paramElements.forEach(function (element) {
        tomarValorDelInput(element);        
    });
};
