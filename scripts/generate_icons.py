import os

icons = {
    "rect-select.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <rect x="6" y="6" width="36" height="36" fill="rgba(74, 144, 217, 0.2)" stroke="#4a90d9" stroke-width="3" stroke-dasharray="6 3"/>
</svg>''',

    "ellipse-select.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="24" cy="24" rx="18" ry="18" fill="rgba(74, 144, 217, 0.2)" stroke="#4a90d9" stroke-width="3" stroke-dasharray="6 3"/>
</svg>''',

    "lasso-select.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path d="M14,36 C6,28 10,10 24,6 C38,2 44,14 40,24 C36,34 30,30 24,42" fill="none" stroke="#4a90d9" stroke-width="3" stroke-dasharray="6 3"/>
  <circle cx="24" cy="42" r="3" fill="#4a90d9"/>
</svg>''',

    "text.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <text x="50%" y="50%" font-family="serif" font-weight="bold" font-size="36" fill="#333" text-anchor="middle" dominant-baseline="central">A</text>
</svg>''',

    "rect-shape.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <rect x="6" y="10" width="36" height="28" fill="#e67e22" stroke="#d35400" stroke-width="2"/>
</svg>''',

    "ellipse-shape.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="24" cy="24" rx="18" ry="14" fill="#e74c3c" stroke="#c0392b" stroke-width="2"/>
</svg>''',

    "rounded-rect-shape.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <rect x="6" y="10" width="36" height="28" rx="8" ry="8" fill="#2ecc71" stroke="#27ae60" stroke-width="2"/>
</svg>''',

    "polygon.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <polygon points="24,4 44,18 36,42 12,42 4,18" fill="#9b59b6" stroke="#8e44ad" stroke-width="2"/>
</svg>''',

    "transform.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <rect x="12" y="12" width="24" height="24" fill="none" stroke="#555" stroke-width="2" stroke-dasharray="4 2"/>
  <path d="M40,8 L36,16 L44,16 Z" fill="#333"/>
  <path d="M8,40 L16,40 L16,32 Z" fill="#333"/>
  <circle cx="24" cy="24" r="3" fill="#e74c3c"/>
</svg>''',

    "color-picker.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path d="M38,10 L34,6 L20,20 L24,24 Z" fill="#7f8c8d"/>
  <path d="M20,20 L24,24 L12,36 L8,36 L8,32 Z" fill="#95a5a6"/>
  <path d="M8,36 L4,44 L12,40 Z" fill="#333"/>
</svg>''',

    "gradient.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:rgb(255,255,0);stop-opacity:1" />
      <stop offset="100%" style="stop-color:rgb(255,0,0);stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect x="6" y="6" width="36" height="36" fill="url(#grad1)" stroke="#333" stroke-width="2"/>
</svg>''',

    "line.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <line x1="8" y1="40" x2="40" y2="8" stroke="#333" stroke-width="4" stroke-linecap="round"/>
</svg>''',

    "curve.svg": '''<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path d="M6,42 C16,10 32,10 42,42" fill="none" stroke="#333" stroke-width="4" stroke-linecap="round"/>
</svg>''',
}

os.makedirs("assets", exist_ok=True)
for name, content in icons.items():
    with open(os.path.join("assets", name), "w") as f:
        f.write(content)

print("Icons generated.")
