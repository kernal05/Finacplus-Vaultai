import React, { useEffect, useRef, useState, useCallback } from "react";
import { CATEGORIES } from "./templates.js";
import { renderPoster } from "./canvasRenderer.js";
import BrowseView from "./BrowseView.jsx";
import Dashboard from "./Dashboard.jsx";
import { saveRecent } from "./recentCreations.js";
import "./App.css";

export default function App() {
  const [view, setView] = useState("home");
  const [browseCategoryId, setBrowseCategoryId] = useState(undefined);
  const [theme, setTheme] = useState(() => localStorage.getItem("vaultai-theme") || "light");

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("vaultai-theme", theme);
  }, [theme]);

  function handleNavigate(nextView, categoryId) {
    setView(nextView);
    if (nextView === "browse") setBrowseCategoryId(categoryId);
  }

  const [categoryId, setCategoryId] = useState(CATEGORIES[0].id);
  const category = CATEGORIES.find((c) => c.id === categoryId);

  const [templateId, setTemplateId] = useState(category.templates[0].id);
  const [name, setName] = useState("");
  const [quote, setQuote] = useState(category.quotes[0]);
  const [photoImg, setPhotoImg] = useState(null);
  const [bgMode, setBgMode] = useState("circle");
  const [aiLoading, setAiLoading] = useState(false);

  const canvasRef = useRef(null);
  const fileInputRef = useRef(null);

  useEffect(() => {
    setTemplateId(category.templates[0].id);
    setQuote(category.quotes[0]);
  }, [categoryId]);

  const template =
    category.templates.find((t) => t.id === templateId) || category.templates[0];

  const draw = useCallback(() => {
    if (!canvasRef.current) return;
    renderPoster(canvasRef.current, { template, name, quote, photoImg, bgMode });
  }, [template, name, quote, photoImg, bgMode]);

  useEffect(() => {
    draw();
  }, [draw]);

  function handlePhoto(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    const img = new Image();
    img.onload = () => setPhotoImg(img);
    img.src = URL.createObjectURL(file);
  }

  function handleDownload() {
    const canvas = canvasRef.current;
    const dataUrl = canvas.toDataURL("image/png");
    const link = document.createElement("a");
    link.download = "vaultai-poster.png";
    link.href = dataUrl;
    link.click();
    saveRecent(dataUrl, category.label);
  }

  async function handleAiCaption() {
    setAiLoading(true);
    try {
      const base = import.meta.env.VITE_API_BASE_URL || "";
      const res = await fetch(`${base}/api/v1/caption`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ topic: category.label }),
      });
      const data = await res.json();
      if (data.caption) setQuote(data.caption);
    } catch (err) {
      console.error("AI caption request failed:", err);
    } finally {
      setAiLoading(false);
    }
  }

  return (
    <div className="app-shell">
      <header className="top-bar">
        <span className="top-bar-brand">VaultAI</span>

        <nav className="view-tabs">
          <button className={`view-tab ${view === "home" ? "active" : ""}`} onClick={() => setView("home")}>
            Home
          </button>
          <button className={`view-tab ${view === "create" ? "active" : ""}`} onClick={() => setView("create")}>
            Create
          </button>
          <button className={`view-tab ${view === "browse" ? "active" : ""}`} onClick={() => setView("browse")}>
            Browse
          </button>
        </nav>

        <button
          className="theme-toggle"
          onClick={() => setTheme(theme === "light" ? "dark" : "light")}
          aria-label="Toggle dark mode"
        >
          {theme === "light" ? "🌙 Dark" : "☀️ Light"}
        </button>
      </header>

      {view === "home" && <Dashboard categories={CATEGORIES} onNavigate={handleNavigate} />}

      {view === "create" && (
        <div className="studio">
          <aside className="rail">
            <nav>
              {CATEGORIES.map((c) => (
                <button
                  key={c.id}
                  className={`rail-item ${c.id === categoryId ? "active" : ""}`}
                  onClick={() => setCategoryId(c.id)}
                >
                  {c.label}
                </button>
              ))}
            </nav>
          </aside>

          <main className="stage">
            <canvas ref={canvasRef} className="poster-canvas" />
          </main>

          <aside className="panel">
            <h1 className="panel-title">{category.label}</h1>

            <section className="panel-section">
              <span className="panel-label">Template</span>
              <div className="swatches">
                {category.templates.map((t) => (
                  <button
                    key={t.id}
                    className={`swatch ${t.id === templateId ? "active" : ""}`}
                    style={{ background: `linear-gradient(135deg, ${t.from}, ${t.to})` }}
                    onClick={() => setTemplateId(t.id)}
                    aria-label={`Template ${t.id}`}
                  />
                ))}
              </div>
            </section>

            <section className="panel-section">
              <span className="panel-label">Your photo</span>
              <button className="btn-secondary" onClick={() => fileInputRef.current?.click()}>
                {photoImg ? "Change photo" : "Upload photo"}
              </button>
              <input ref={fileInputRef} type="file" accept="image/*" hidden onChange={handlePhoto} />

              {photoImg && (
                <div className="bg-mode-toggle">
                  <button className={bgMode === "circle" ? "active" : ""} onClick={() => setBgMode("circle")}>
                    Framed photo
                  </button>
                  <button className={bgMode === "photo" ? "active" : ""} onClick={() => setBgMode("photo")}>
                    Full background
                  </button>
                </div>
              )}
            </section>

            <section className="panel-section">
              <span className="panel-label">Name</span>
              <input
                className="text-input"
                placeholder="Your name"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </section>

            <section className="panel-section">
              <span className="panel-label">Message</span>
              <textarea
                className="text-input textarea"
                value={quote}
                onChange={(e) => setQuote(e.target.value)}
                rows={4}
              />
              <button className="btn-ghost" onClick={handleAiCaption} disabled={aiLoading}>
                {aiLoading ? "Thinking…" : "✦ Suggest with AI"}
              </button>
            </section>

            <button className="btn-primary" onClick={handleDownload}>
              Download poster
            </button>
          </aside>
        </div>
      )}

      {view === "browse" && (
        <BrowseView key={browseCategoryId || "default"} categories={CATEGORIES} initialCategoryId={browseCategoryId} />
      )}
    </div>
  );
}
