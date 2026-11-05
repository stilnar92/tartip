// Sections fade and rise in as they scroll into view; the nav gets a hairline once you scroll.
document.documentElement.classList.add("js");
const io = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
}, { rootMargin: "0px 0px -12% 0px" });
document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

const nav = document.querySelector(".nav");
const onScroll = () => nav.classList.toggle("scrolled", scrollY > 8);
addEventListener("scroll", onScroll, { passive: true });
onScroll();
