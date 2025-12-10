let currentMenuOptions = [];
let selectedIndex = 0;
let isMenuOpen = false;
let progressInterval = null;

$(document).ready(function () {
    window.addEventListener('message', function (event) {
        let data = event.data;
        if (data.action === "openMenu") {
            openMenu(data.title, data.options);
        } else if (data.action === "closeMenu") {
            closeMenu();
        } else if (data.action === "startProgress") {
            startProgress(data.label, data.duration);
        } else if (data.action === "stopProgress") {
            stopProgress();
        }
    });

    document.onkeydown = function (data) {
        if (isMenuOpen) {
            if (data.which == 38) { // Up
                selectedIndex--;
                if (selectedIndex < 0) selectedIndex = currentMenuOptions.length - 1;
                updateSelection();
            } else if (data.which == 40) { // Down
                selectedIndex++;
                if (selectedIndex >= currentMenuOptions.length) selectedIndex = 0;
                updateSelection();
            } else if (data.which == 13) { // Enter
                selectOption();
            } else if (data.which == 8) { // Backspace
                closeMenu();
                $.post('https://rsg-moonshiner/closeMenu', JSON.stringify({}));
            }
        }
    };
});

function openMenu(title, options) {
    $("#menu-title").text(title);
    $("#menu-options-list").empty();
    currentMenuOptions = options;
    selectedIndex = 0;

    options.forEach((opt, index) => {
        let el = $(`
            <div class="menu-option" id="opt-${index}">
                <div class="title">${opt.title}</div>
                <div class="description">${opt.description || ''}</div>
            </div>
        `);

        el.click(function () {
            selectedIndex = index;
            updateSelection();
            selectOption();
        });

        // If it has a specific icon, we could add it back if we passed it
        $("#menu-options-list").append(el);
    });

    updateSelection();
    $("#menu-interface").removeClass("hidden");
    isMenuOpen = true;
}

function updateSelection() {
    $(".menu-option").removeClass("selected");
    $(`#opt-${selectedIndex}`).addClass("selected");

    // Auto scroll
    let el = document.getElementById(`opt-${selectedIndex}`);
    if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

function selectOption() {
    let opt = currentMenuOptions[selectedIndex];
    if (opt) {
        $.post('https://rsg-moonshiner/selectOption', JSON.stringify({
            index: selectedIndex + 1,
            data: opt
        }));
    }
}

function closeMenu() {
    $("#menu-interface").addClass("hidden");
    isMenuOpen = false;
}

function startProgress(label, duration) {
    $("#progress-label").text(label);
    $("#progress-fill").css("width", "0%");
    $("#progress-text").text("0%");

    // Clear any pending hide
    $("#progress-interface").removeClass("hidden");

    let startTime = Date.now();

    if (progressInterval) clearInterval(progressInterval);

    progressInterval = setInterval(() => {
        let now = Date.now();
        let pct = ((now - startTime) / duration) * 100;

        if (pct >= 100) {
            pct = 100;
            clearInterval(progressInterval);
            $.post('https://rsg-moonshiner/progressComplete', JSON.stringify({}));
        }

        $("#progress-fill").css("width", pct + "%");
        $("#progress-text").text(Math.floor(pct) + "%");
    }, 50);
}

function stopProgress() {
    if (progressInterval) clearInterval(progressInterval);
    $("#progress-interface").addClass("hidden");
}
