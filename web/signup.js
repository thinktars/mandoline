// Email-capture modal: gate the macOS download behind a single email field,
// POST it to /api/signup (captured in D1), then start the download.
(function () {
  "use strict";

  var DMG = "Mandoline.dmg";
  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  var modal = document.getElementById("signup-modal");
  var form = document.getElementById("signup-form");
  var email = document.getElementById("signup-email");
  var err = document.getElementById("signup-error");
  var submit = document.getElementById("signup-submit");
  var closeBtn = document.getElementById("signup-close");
  if (!modal || !form) return;

  var supportsDialog = typeof modal.showModal === "function";

  function resetButton() {
    submit.classList.remove("is-loading", "is-done");
    submit.disabled = false;
  }

  function open() {
    err.hidden = true;
    email.value = "";
    resetButton();
    if (supportsDialog) modal.showModal();
    else modal.setAttribute("open", "");
    setTimeout(function () { email.focus(); }, 60);
  }
  function close() {
    if (supportsDialog) modal.close();
    else modal.removeAttribute("open");
  }

  function startDownload() {
    var a = document.createElement("a");
    a.href = DMG;
    a.setAttribute("download", "");
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  // Intercept any download trigger and show the modal instead.
  document.querySelectorAll("[data-download]").forEach(function (btn) {
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      open();
    });
  });

  closeBtn.addEventListener("click", close);
  // Click on the backdrop (outside the card) closes the dialog.
  modal.addEventListener("click", function (e) {
    if (e.target === modal) close();
  });

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var value = email.value.trim();
    if (!EMAIL_RE.test(value) || value.length > 254) {
      err.textContent = "Please enter a valid email address.";
      err.hidden = false;
      email.focus();
      return;
    }

    submit.disabled = true;
    submit.classList.add("is-loading");
    err.hidden = true;

    fetch("/api/signup", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: value, referrer: document.referrer, source: "download_modal" })
    })
      .then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (data) {
          return { ok: res.ok, data: data };
        });
      })
      .then(function (r) {
        if (!r.ok || !r.data.ok) {
          throw new Error((r.data && r.data.error) || "Something went wrong. Please try again.");
        }
        // Animate the download icon, start the download, then close.
        submit.classList.remove("is-loading");
        submit.classList.add("is-done");
        setTimeout(function () {
          startDownload();
          close();
          resetButton();
        }, 450);
      })
      .catch(function (ex) {
        submit.classList.remove("is-loading");
        submit.disabled = false;
        err.textContent = ex.message || "Could not save your email. Please try again.";
        err.hidden = false;
      });
  });
})();
