import React, { useState, useEffect, useRef, useCallback } from "react";
import { renderPoster } from "./canvasRenderer.js";
import { saveRecent } from "./recentCreations.js";
import "./BrowseView.css";

function luminance(hex) {
  const c = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(c.substr(i, 2), 16) / 255);
  const lin = (v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function cardTextColor(template) {
  const avg = (luminance(template.from) + luminance(template.to)) / 2;
  return avg > 0.4 ? "#1b1712" : "#f5efe2";
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      // fall through to legacy method
    }
  }
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.left = "-9999px";
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  let ok = false;
  try {
    ok = document.execCommand("copy");
  } catch (e) {
    ok = false;
  }
  document.body.removeChild(ta);
  return ok;
}

export default function BrowseView({ categories, initialCategoryId }) {
  const [categoryId, setCategoryId] = useState(initialCategoryId || categories[0].id);
  const category = categories.find((c) => c.id === categoryId) || categories[0];
  const [quotes, setQuotes] = useState(category.quotes);
  const [loading, setLoading] = useState(false);
  const [copiedIndex, setCopiedIndex] = useState(null);
  const hiddenCanvasRef = useRef(null);

  const fetchQuotes = useCallback(async (cat) => {
    setLoading(true);
    try {
      const base = import.meta.env.VITE_API_BASE_URL || "";
      const res = await fetch(`${base}/api/v1/quotes`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ topic: cat.label, count: 8 }),
      });
      const data = await res.json();
      if (Array.isArray(data.quotes) && data.quotes.length) {
        setQuotes(data.quotes);
      } else {
        setQuotes(cat.quotes);
      }
    } catch (err) {
      console.error("quotes fetch failed:", err);
      setQuotes(cat.quotes);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchQuotes(category);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [categoryId]);

  async function handleCopy(text, idx) {
    const ok = await copyText(text);
    if (ok) {
      setCopiedIndex(idx);
      setTimeout(() => setCopiedIndex(null), 1500);
    } else {
      alert("Couldn't copy automatically — select and copy the text manually.");
    }
  }

  function handleDownload(text, idx) {
    const canvas = hiddenCanvasRef.current;
    const t = category.templates[idx % category.templates.length];
    renderPoster(canvas, { template: t, name: "", quote: text, photoImg: null, bgMode: "circle" });
    const dataUrl = canvas.toDataURL("image/png");
    const link = document.createElement("a");
    link.download = `vaultai-${category.id}-${idx + 1}.png`;
    link.href = dataUrl;
    link.click();
    saveRecent(dataUrl, category.label);
  }

  async function handleShare(text) {
    if (navigator.share && window.isSecureContext) {
      try {
        await navigator.share({ text, title: "VaultAI" });
        return;
      } catch (err) {
        return;
      }
    }
    const ok = await copyText(text);
    alert(ok ? "Copied — share it anywhere you like." : "Couldn't copy automatically — select and copy the text manually.");
  }

  return (
    <div className="browse">
      <nav className="browse-tabs">
        {categories.map((c) => (
          <button
            key={c.id}
            className={`browse-tab ${c.id === categoryId ? "active" : ""}`}
            onClick={() => setCategoryId(c.id)}
          >
            {c.label}
          </button>
        ))}
      </nav>

      <h1 className="browse-title">{category.label}</h1>

      {loading ? (
        <div className="browse-loading">Generating fresh ones…</div>
      ) : (
        <div className="browse-grid">
          {quotes.map((q, idx) => {
            const t = category.templates[idx % category.templates.length];
            const fg = cardTextColor(t);
            return (
              <article
                key={idx}
                className="quote-card"
                style={{ background: `linear-gradient(135deg, ${t.from}, ${t.to})`, "--card-fg": fg }}
              >
                <p className="quote-text">{q}</p>
                <div className="quote-actions">
                  <button onClick={() => handleCopy(q, idx)}>{copiedIndex === idx ? "Copied" : "Copy"}</button>
                  <button onClick={() => handleDownload(q, idx)}>Download</button>
                  <button onClick={() => handleShare(q)}>Share</button>
                </div>
              </article>
            );
          })}
        </div>
      )}

      <canvas ref={hiddenCanvasRef} className="hidden-canvas" />
    </div>
  );
}
