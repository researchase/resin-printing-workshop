/* =========================================================================
   EDIT ME  —  workshop quotes
   -------------------------------------------------------------------------
   Replace the text below with things people actually said, then delete the
   `placeholder: true` line from each entry to remove the amber PLACEHOLDER
   tag from the card. Add or remove entries freely — the grid reflows.

   These are deliberately left as templates: real names and real quotes are
   yours to collect, not mine to invent.
   ========================================================================= */

const QUOTES = [
  {
    // Posted in the school parents' group after the workshop. Quoted verbatim.
    text: "Кому что, а нам котиков и побольше 🐈‍⬛🐈‍⬛🐈‍⬛ Thank a lot @researchase for a fun hands on experience with 3D printer",
    note: "“To each their own — for us it's cats, and more of them.”",
    who: "Ekaterina L.",
    role: "Parent, school group",
  },
];

/* ------------------------------------------------------------------ render */

function renderQuotes() {
  const grid = document.getElementById("quote-grid");
  if (!grid) return;
  if (!QUOTES.length) {
    grid.closest("section").hidden = true;
    return;
  }
  // a lone quote reads better as one centred pull-quote than a stranded card
  grid.classList.toggle("single", QUOTES.length === 1);
  grid.innerHTML = QUOTES.map((q) => `
    <figure class="quote io">
      ${q.placeholder ? '<span class="quote-tag">placeholder — edit me</span>' : ""}
      <blockquote class="quote-text">${escapeHtml(q.text)}</blockquote>
      ${q.note ? `<p class="quote-note">${escapeHtml(q.note)}</p>` : ""}
      <figcaption class="quote-who">
        ${escapeHtml(q.who)}${q.role ? ` <span class="quote-role">· ${escapeHtml(q.role)}</span>` : ""}
      </figcaption>
    </figure>
  `).join("");
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]);
}

/* --------------------------------------------------- scroll-in transitions */

function observeReveals() {
  const targets = document.querySelectorAll(
    ".step-copy, .shot, .model-head, .viewer-wrap, .specs, .footnote, .voices h2, .voices .stepno, .quote, .cta-inner"
  );
  targets.forEach((el) => el.classList.add("io"));

  if (!("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry, i) => {
        if (!entry.isIntersecting) return;
        // small stagger for groups that come into view together
        setTimeout(() => entry.target.classList.add("in"), i * 70);
        io.unobserve(entry.target);
      });
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.12 }
  );
  targets.forEach((el) => io.observe(el));
}

renderQuotes();
observeReveals();
