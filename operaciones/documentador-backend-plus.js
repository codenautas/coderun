window.onload = function () {
    var placeHolder = {}
    var codeElement = document.querySelectorAll("pre")
    codeElement.forEach(function (element) {
        console.log("x:", element.innerText.split(/(\$(?:\{\w+\}|\w+))/))
        var code = element.innerText.split(/(\$(?:\{\w+\}|\w+))/).map(function (part, i) {
            if (i % 2 === 0) {
                return document.createTextNode(part); // Texto normal
            } else {
                var span = document.createElement("span");
                var variable = part.replace(/^\{?|\}?$/g, "");
                span.setAttribute("bp-variable", variable)
                span.textContent = part;
                return span;
            }
        });
        element.innerHTML = "";
        element.append(...code);
    });
    console.log("Página cargada correctamente");
};
