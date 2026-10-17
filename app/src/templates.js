// All templates are procedural (gradients drawn on <canvas>), not copied
// images — keeps this clean of any existing app's actual assets.

export const CATEGORIES = [
  {
    id: "morning",
    label: "Good Morning",
    quotes: [
      "Rise with the sun, shine like it too.",
      "A fresh page. Write something good on it today.",
      "Morning light, quiet mind, steady heart.",
    ],
    templates: [
      { id: "m1", from: "#F2C14E", to: "#E8A23D", motif: "rays" },
      { id: "m2", from: "#EFE6D3", to: "#E8A23D", motif: "waves" },
      { id: "m3", from: "#7A2438", to: "#F2C14E", motif: "rays" },
      { id: "m4", from: "#E8A23D", to: "#7A2438", motif: "diamond" },
      { id: "m5", from: "#F2C14E", to: "#1B2A4A", motif: "waves" },
    ],
  },
  {
    id: "motivation",
    label: "Motivational",
    quotes: [
      "Small steps, repeated daily, outrun big leaps taken rarely.",
      "Discipline is choosing what you want most over what you want now.",
      "Start before you're ready. Ready rarely comes first.",
    ],
    templates: [
      { id: "mo1", from: "#1B2A4A", to: "#7A2438", motif: "grid" },
      { id: "mo2", from: "#101A30", to: "#1B2A4A", motif: "diagonal" },
      { id: "mo3", from: "#7A2438", to: "#1B2A4A", motif: "waves" },
      { id: "mo4", from: "#101A30", to: "#7A2438", motif: "grid" },
      { id: "mo5", from: "#E8A23D", to: "#101A30", motif: "diagonal" },
    ],
  },
  {
    id: "festival",
    label: "Festival",
    quotes: [
      "Warm lights, warmer company. Happy festivities.",
      "May this season bring color to every corner of your life.",
      "Celebrate loudly, love deeply, laugh often.",
    ],
    templates: [
      { id: "f1", from: "#7A2438", to: "#E8A23D", motif: "diamond" },
      { id: "f2", from: "#E8A23D", to: "#F2C14E", motif: "diamond" },
      { id: "f3", from: "#1B2A4A", to: "#E8A23D", motif: "waves" },
      { id: "f4", from: "#7A2438", to: "#F2C14E", motif: "grid" },
      { id: "f5", from: "#F2C14E", to: "#7A2438", motif: "rays" },
    ],
  },
  {
    id: "business",
    label: "Business",
    quotes: [
      "Consistency compounds. Show up again tomorrow.",
      "Good work, done quietly, speaks the loudest.",
      "Build the thing you'd want to buy.",
    ],
    templates: [
      { id: "b1", from: "#101A30", to: "#1B2A4A", motif: "grid" },
      { id: "b2", from: "#1B2A4A", to: "#4A4339", motif: "diagonal" },
      { id: "b3", from: "#EFE6D3", to: "#1B2A4A", motif: "grid" },
      { id: "b4", from: "#4A4339", to: "#101A30", motif: "diagonal" },
      { id: "b5", from: "#E8A23D", to: "#1B2A4A", motif: "grid" },
    ],
  },
  {
    id: "skincare",
    label: "Skin Care Tips",
    quotes: [
      "Wash your face twice daily with a gentle, sulfate-free cleanser.",
      "Never skip sunscreen, even indoors near a window.",
      "Moisturize while skin is still damp — it locks in more hydration.",
    ],
    templates: [
      { id: "sk1", from: "#F2C14E", to: "#EFE6D3", motif: "waves" },
      { id: "sk2", from: "#E8A23D", to: "#F2C14E", motif: "diamond" },
      { id: "sk3", from: "#7A2438", to: "#E8A23D", motif: "rays" },
    ],
  },
  {
    id: "fitness",
    label: "Fitness Tips",
    quotes: [
      "Consistency beats intensity — a 20-minute walk daily wins long-term.",
      "Warm up for 5 minutes before any workout to protect your joints.",
      "Progress isn't always the scale — track how your clothes fit too.",
    ],
    templates: [
      { id: "fi1", from: "#1B2A4A", to: "#E8A23D", motif: "grid" },
      { id: "fi2", from: "#101A30", to: "#7A2438", motif: "diagonal" },
      { id: "fi3", from: "#7A2438", to: "#1B2A4A", motif: "rays" },
    ],
  },
  {
    id: "study",
    label: "Study Tips",
    quotes: [
      "Study in short, focused blocks — 25 minutes on, 5 minutes off.",
      "Explaining a topic out loud reveals what you actually understand.",
      "Review notes within 24 hours — it's when forgetting happens fastest.",
    ],
    templates: [
      { id: "st1", from: "#EFE6D3", to: "#1B2A4A", motif: "grid" },
      { id: "st2", from: "#F2C14E", to: "#1B2A4A", motif: "waves" },
      { id: "st3", from: "#E8A23D", to: "#101A30", motif: "diagonal" },
    ],
  },
];
