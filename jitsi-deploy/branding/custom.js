(function () {
    var target = 'Stormyra Meet';
    function fixTitle() {
        if (document.title !== target) {
            document.title = target;
        }
    }
    fixTitle();
    var titleEl = document.querySelector('title');
    if (titleEl) {
        new MutationObserver(fixTitle).observe(titleEl, { childList: true });
    }
})();
