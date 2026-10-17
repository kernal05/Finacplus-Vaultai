const W = 1080;
const H = 1350; // WhatsApp status / portrait poster ratio

function drawMotif(ctx, motif, color) {
  ctx.save();
  ctx.globalAlpha = 0.14;
  ctx.strokeStyle = color;
  ctx.fillStyle = color;

  if (motif === "rays") {
    ctx.translate(W / 2, H * 0.15);
    for (let i = 0; i < 16; i++) {
      ctx.rotate((Math.PI * 2) / 16);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, -W * 0.9);
      ctx.lineWidth = 6;
      ctx.stroke();
    }
  } else if (motif === "waves") {
    ctx.lineWidth = 3;
    for (let y = 0; y < H; y += 60) {
      ctx.beginPath();
      for (let x = 0; x <= W; x += 20) {
        const yy = y + Math.sin((x / W) * Math.PI * 4) * 18;
        x === 0 ? ctx.moveTo(x, yy) : ctx.lineTo(x, yy);
      }
      ctx.stroke();
    }
  } else if (motif === "grid") {
    ctx.lineWidth = 1.5;
    for (let x = 0; x <= W; x += 54) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, H);
      ctx.stroke();
    }
    for (let y = 0; y <= H; y += 54) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(W, y);
      ctx.stroke();
    }
  } else if (motif === "diagonal") {
    ctx.lineWidth = 2;
    for (let i = -H; i < W; i += 46) {
      ctx.beginPath();
      ctx.moveTo(i, 0);
      ctx.lineTo(i + H, H);
      ctx.stroke();
    }
  } else if (motif === "diamond") {
    const s = 70;
    for (let y = -s; y < H + s; y += s) {
      for (let x = -s; x < W + s; x += s) {
        const off = (y / s) % 2 === 0 ? 0 : s / 2;
        ctx.beginPath();
        ctx.moveTo(x + off, y);
        ctx.lineTo(x + off + s / 2, y + s / 2);
        ctx.lineTo(x + off, y + s);
        ctx.lineTo(x + off - s / 2, y + s / 2);
        ctx.closePath();
        ctx.stroke();
      }
    }
  }
  ctx.restore();
}

function wrapText(ctx, text, x, y, maxWidth, lineHeight) {
  const words = text.split(" ");
  let line = "";
  const lines = [];
  for (const word of words) {
    const test = line + word + " ";
    if (ctx.measureText(test).width > maxWidth && line !== "") {
      lines.push(line.trim());
      line = word + " ";
    } else {
      line = test;
    }
  }
  lines.push(line.trim());
  lines.forEach((l, i) => ctx.fillText(l, x, y + i * lineHeight));
  return lines.length;
}

function drawGradientBackground(ctx, template) {
  const grad = ctx.createLinearGradient(0, 0, W, H);
  grad.addColorStop(0, template.from);
  grad.addColorStop(1, template.to);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, W, H);
  drawMotif(ctx, template.motif, "#EFE6D3");
}

function drawPhotoBackground(ctx, template, photoImg) {
  // Cover-fit the photo across the whole canvas
  const scale = Math.max(W / photoImg.width, H / photoImg.height);
  const iw = photoImg.width * scale;
  const ih = photoImg.height * scale;
  ctx.drawImage(photoImg, (W - iw) / 2, (H - ih) / 2, iw, ih);

  // Duotone-style color overlay so the photo matches the chosen template
  const grad = ctx.createLinearGradient(0, 0, W, H);
  grad.addColorStop(0, template.from);
  grad.addColorStop(1, template.to);
  ctx.save();
  ctx.globalAlpha = 0.4;
  ctx.globalCompositeOperation = "multiply";
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, W, H);
  ctx.restore();
}

export function renderPoster(canvas, { template, name, quote, photoImg, bgMode = "circle" }) {
  const ctx = canvas.getContext("2d");
  canvas.width = W;
  canvas.height = H;

  const usePhotoBg = bgMode === "photo" && !!photoImg;

  if (usePhotoBg) {
    drawPhotoBackground(ctx, template, photoImg);
  } else {
    drawGradientBackground(ctx, template);
  }

  // Bottom scrim so text stays legible over any motif or photo
  const scrim = ctx.createLinearGradient(0, H * 0.5, 0, H);
  scrim.addColorStop(0, "rgba(16,26,48,0)");
  scrim.addColorStop(1, "rgba(16,26,48,0.75)");
  ctx.fillStyle = scrim;
  ctx.fillRect(0, H * 0.5, W, H * 0.5);

  let quoteY = H * 0.68;

  // Circular framed photo — only in circle mode
  if (photoImg && !usePhotoBg) {
    const r = 130;
    const cx = W / 2;
    const cy = H * 0.62;
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.closePath();
    ctx.clip();
    const scale = Math.max((r * 2) / photoImg.width, (r * 2) / photoImg.height);
    const iw = photoImg.width * scale;
    const ih = photoImg.height * scale;
    ctx.drawImage(photoImg, cx - iw / 2, cy - ih / 2, iw, ih);
    ctx.restore();

    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.lineWidth = 6;
    ctx.strokeStyle = "#EFE6D3";
    ctx.stroke();

    quoteY = cy + 190;
  }

  // Quote
  ctx.fillStyle = "#EFE6D3";
  ctx.font = "600 44px Fraunces, serif";
  ctx.textAlign = "center";
  wrapText(ctx, quote, W / 2, quoteY, W - 160, 54);

  // Name
  if (name) {
    ctx.font = "500 30px Inter, sans-serif";
    ctx.fillStyle = "#F2C14E";
    ctx.fillText(`— ${name}`, W / 2, H - 70);
  }

  // Brand mark
  ctx.textAlign = "left";
  ctx.font = "600 24px Fraunces, serif";
  ctx.fillStyle = "rgba(239,230,211,0.85)";
  ctx.fillText("VaultAI", 48, 64);
}

export { W, H };
