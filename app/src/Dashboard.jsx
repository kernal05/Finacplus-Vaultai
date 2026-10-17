import React, { useState, useEffect } from "react";
import { getRecent } from "./recentCreations.js";
import "./Dashboard.css";

export default function Dashboard({ categories, onNavigate }) {
  const [recent, setRecent] = useState([]);

  useEffect(() => {
    setRecent(getRecent());
  }, []);

  return (
    <div className="dashboard">
      <h1 className="dash-greeting">Welcome to VaultAI</h1>
      <p className="dash-subtitle">Make a poster, browse ready-made ideas, or pick up where you left off.</p>

      <div className="dash-tiles">
        <button className="dash-tile dash-tile-create" onClick={() => onNavigate("create")}>
          <span className="dash-tile-title">Create a poster</span>
          <span className="dash-tile-sub">Photo, name, message — download in seconds</span>
        </button>
        <button className="dash-tile dash-tile-browse" onClick={() => onNavigate("browse")}>
          <span className="dash-tile-title">Browse ideas</span>
          <span className="dash-tile-sub">AI-generated quotes and tips, ready to use</span>
        </button>
      </div>

      <h2 className="dash-section-title">Categories</h2>
      <div className="dash-category-grid">
        {categories.map((c) => {
          const t = c.templates[0];
          return (
            <button
              key={c.id}
              className="dash-category-tile"
              onClick={() => onNavigate("browse", c.id)}
            >
              <span
                className="dash-category-swatch"
                style={{ display: "block", background: `linear-gradient(135deg, ${t.from}, ${t.to})` }}
              />
              <span className="dash-category-label">{c.label}</span>
            </button>
          );
        })}
      </div>

      <h2 className="dash-section-title">Recent creations</h2>
      {recent.length === 0 ? (
        <p className="dash-empty-recent">Nothing yet — posters you download will show up here.</p>
      ) : (
        <div className="dash-recent-row">
          {recent.map((r, i) => (
            <img key={i} src={r.dataUrl} alt={r.label} className="dash-recent-thumb" />
          ))}
        </div>
      )}
    </div>
  );
}
