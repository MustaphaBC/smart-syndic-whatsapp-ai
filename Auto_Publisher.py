import asyncio
import json
import os
import glob
import hashlib
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
import asyncpg
import httpx
from dotenv import load_dotenv
from groq import Groq
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from playwright.async_api import async_playwright  

load_dotenv()

# ══════════════════════════════════════════════════════════════════════
# CONFIG
# ══════════════════════════════════════════════════════════════════════
PROJECT_ROOT = Path(__file__).parent

DB_CONFIG = {
    "host":     os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "pfe_db"),
    "user":     os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
}

FB_PAGE_ACCESS_TOKEN = os.getenv("FB_PAGE_ACCESS_TOKEN")
FB_PAGE_ID           = os.getenv("FB_PAGE_ID")
FB_API_VERSION       = "v25.0"
FB_API_BASE          = f"https://graph.facebook.com/{FB_API_VERSION}"

# Configuration du Groupe (Playwright)
FB_GROUP_URL  = os.getenv("FB_GROUP_URL", "")
FB_GROUP_URLS = os.getenv("FB_GROUP_URLS", "")  # "url1,url2,url3" pour plusieurs groupes
COOKIES_FILE = PROJECT_ROOT / "sessions" / "facebook-cookies.json"

GROQ_API_KEY  = os.getenv("GROQ_API_KEY")
LLM_MODEL     = "llama-3.3-70b-versatile"
UNITS_JSON    = "data/units.json"
ASSETS_DIR    = Path("assets")
OUTPUT_DIR    = Path("generated_announcements")
OUTPUT_DIR.mkdir(exist_ok=True)

# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — RÉSOUDRE LES IMAGES D'UNE UNITÉ
# ══════════════════════════════════════════════════════════════════════
def get_unit_images(unit: dict, max_images: int = 10) -> list[str]:
    found = []
    # ── 1. Chemin JSON ────────────────────────────────────────────────
    for img_path in unit.get("images", []):
        p = Path(img_path)
        if p.exists() and p.is_file():
            found.append(str(p))
        if len(found) >= max_images:
            return found
    if found:
        return found
    # ── 2. Auto-scan dossier assets ───────────────────────────────────
    unit_dir = ASSETS_DIR / unit["residence_id"] / unit["unit_number"]
    if unit_dir.exists():
        numbered = sorted(
            unit_dir.glob("img*.jpg"),
            key=lambda p: int(''.join(filter(str.isdigit, p.stem)) or '0')
        )
        for p in numbered:
            if p.is_file():
                found.append(str(p))
            if len(found) >= max_images:
                return found
        if len(found) < max_images:
            for ext in ["*.jpeg", "*.png", "*.webp"]:
                for p in sorted(unit_dir.glob(ext)):
                    if str(p) not in found and p.is_file():
                        found.append(str(p))
                    if len(found) >= max_images:
                        return found
    if not found:
        print(f"  ⚠️  Aucune image: assets/{unit['residence_id']}/{unit['unit_number']}/")
    return found

def get_best_cover_image(unit: dict) -> Optional[str]:
    images = get_unit_images(unit, max_images=1)
    return images[0] if images else None
# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — CRÉER L'IMAGE COLLAGE 
# ══════════════════════════════════════════════════════════════════════
def create_fallback_poster(unit: dict, output_path: str) -> str:
    W, H = 1200, 900
    C_BG     = (15, 23, 42)
    C_ACCENT = (37, 99, 235)
    C_CARD   = (30, 41, 59)
    C_TEXT   = (248, 250, 252)
    C_MUTED  = (100, 116, 139)
    C_GREEN  = (22, 163, 74)
    img  = Image.new("RGB", (W, H), C_BG)
    draw = ImageDraw.Draw(img)
    try:
        fB = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 50)
        fM = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 34)
        fN = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 26)
        fS = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
    except Exception:
        fB = fM = fN = fS = ImageFont.load_default()
    # Bande header
    draw.rectangle([0, 0, W, 95], fill=C_ACCENT)
    draw.text((45, 26), "🏢  APPARTEMENT À LOUER — DISPONIBLE MAINTENANT", font=fM, fill="white")
    # Titre résidence
    draw.text((45, 120), unit.get("residence_name", unit["residence_id"]).upper(), font=fB, fill=C_TEXT)
    draw.text((45, 184), f"📍 {unit.get('city', '')} — {unit.get('address', '')}", font=fN, fill=C_MUTED)
    draw.rectangle([45, 230, W - 45, 233], fill=C_ACCENT)
    # 4 stat cards
    cards = [
        ("🏠 Surface",   f"{unit.get('surface', '?')} m²"),
        ("🛏️ Pièces",    f"{unit.get('rooms', '?')} pièces"),
        ("📊 Étage",     f"Étage {unit.get('floor', '?')}"),
        ("🔑 Appartement", f"N° {unit['unit_number']}"),
    ]
    for idx, (label, val) in enumerate(cards):
        col, row = idx % 2, idx // 2
        x = 45 + col * 590
        y = 255 + row * 130
        draw.rounded_rectangle([x, y, x + 555, y + 110], radius=14,
                                fill=C_CARD, outline=C_ACCENT, width=2)
        draw.text((x + 18, y + 14), label, font=fS, fill=C_MUTED)
        draw.text((x + 18, y + 48), val,   font=fM, fill=C_TEXT)
    # Features
    feats = unit.get("features", [])[:6]
    if feats:
        draw.text((45, 535), "✅  Équipements : " + "   •   ".join(feats), font=fN, fill=C_MUTED)
    # Prix
    draw.rounded_rectangle([45, 575, W - 45, 668], radius=16, fill=C_ACCENT)
    draw.text((W // 2 - 200, 595), f"💰  {unit.get('price', '?')} MAD / mois", font=fB, fill="white")
    # Description
    desc = unit.get("description", "")[:120]
    draw.text((45, 690), desc, font=fN, fill=C_MUTED)
    # Contact
    contact = unit.get("contact_phone", "")
    if contact:
        draw.text((45, 740), f"📱  WhatsApp : {contact}", font=fM, fill=C_TEXT)
    # Footer
    draw.rectangle([0, 830, W, H], fill=C_CARD)
    draw.text((45, 850), f"Syndic IA  •  {datetime.now().strftime('%d/%m/%Y')}",
              font=fS, fill=C_MUTED)
    draw.text((W - 450, 850), "#ImmobilierMaroc #LocationMaroc #Appartement",
              font=fS, fill=C_ACCENT)
    img.save(output_path, quality=95)
    return output_path

def create_multi_image_collage(images: list[str], unit: dict, output_path: str) -> str:
    W, H     = 1200, 800
    C_BG     = (15, 23, 42)
    C_ACCENT = (37, 99, 235)
    C_TEXT   = (248, 250, 252)
    C_MUTED  = (100, 116, 139)

    canvas = Image.new("RGB", (W, H), C_BG)
    draw   = ImageDraw.Draw(canvas)

    try:
        fB = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 38)
        fM = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 26)
        fN = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 21)
        fS = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 17)
    except Exception:
        fB = fM = fN = fS = ImageFont.load_default()

    # ── Zone info droite (30% de la largeur) ─────────────────────────
    INFO_W   = 340
    PHOTO_W  = W - INFO_W   # 860px
    GAP      = 4             # espacement entre photos

    def _load_photo(path: str, w: int, h: int) -> Image.Image:
        img = Image.open(path).convert("RGB")
        src_w, src_h = img.size
        target_ratio = w / h
        src_ratio    = src_w / src_h
        if src_ratio > target_ratio:
            new_w = int(src_h * target_ratio)
            left  = (src_w - new_w) // 2
            img   = img.crop((left, 0, left + new_w, src_h))
        else:
            new_h = int(src_w / target_ratio)
            top   = (src_h - new_h) // 2
            img   = img.crop((0, top, src_w, top + new_h))
        return img.resize((w, h), Image.LANCZOS)

    # ── Layout photos ─────────────────────────────────────────────────
    n = len(images)

    if n == 1:
        # Plein cadre
        photo = _load_photo(images[0], PHOTO_W, H)
        canvas.paste(photo, (0, 0))

    elif n == 2:
        # Haut + Bas
        h1 = H // 2 - GAP // 2
        h2 = H - h1 - GAP
        canvas.paste(_load_photo(images[0], PHOTO_W, h1), (0, 0))
        canvas.paste(_load_photo(images[1], PHOTO_W, h2), (0, h1 + GAP))

    elif n == 3:
        # Grande gauche + 2 petites droite
        big_w  = PHOTO_W * 60 // 100
        sml_w  = PHOTO_W - big_w - GAP
        sml_h  = H // 2 - GAP // 2
        canvas.paste(_load_photo(images[0], big_w, H), (0, 0))
        canvas.paste(_load_photo(images[1], sml_w, sml_h), (big_w + GAP, 0))
        canvas.paste(_load_photo(images[2], sml_w, H - sml_h - GAP), (big_w + GAP, sml_h + GAP))

    else:
        # Grande gauche + 3 petites droite en colonne (4+ images)
        big_w = PHOTO_W * 60 // 100
        sml_w = PHOTO_W - big_w - GAP
        n_right = min(n - 1, 3)
        sml_h = H // n_right - GAP // n_right
        canvas.paste(_load_photo(images[0], big_w, H), (0, 0))
        for i in range(n_right):
            y = i * (sml_h + GAP)
            canvas.paste(_load_photo(images[i + 1], sml_w, sml_h), (big_w + GAP, y))
        # Badge "+N photos" si plus de 4 images
        if n > 4:
            extra = n - 4
            overlay_x = big_w + GAP
            overlay_y = H - sml_h
            draw.rectangle(
                [overlay_x, overlay_y, overlay_x + sml_w, H],
                fill=(0, 0, 0)
            )
            draw.text(
                (overlay_x + sml_w // 2 - 40, overlay_y + sml_h // 2 - 15),
                f"+{extra} photos",
                font=fM, fill="white"
            )

    # ── Overlay gradient sur la gauche pour lisibilité du texte ───────
    for y_off in range(160):
        alpha = int(200 * y_off / 160)
        draw.line(
            [(0, H - 160 + y_off), (PHOTO_W, H - 160 + y_off)],
            fill=(0, 0, 0, alpha)
        )

    # ── Panneau infos (droite) ────────────────────────────────────────
    info_x = PHOTO_W
    draw.rectangle([info_x, 0, W, H], fill=C_BG)

    # Badge disponible
    draw.rounded_rectangle([info_x + 16, 16, info_x + 180, 48],
                            radius=8, fill=(22, 163, 74))
    draw.text((info_x + 26, 24), "✅ DISPONIBLE", font=fS, fill="white")

    # Nom résidence
    res_name = unit.get("residence_name", unit["residence_id"])
    # Wrap si trop long
    words = res_name.upper().split()
    line1, line2 = "", ""
    for w in words:
        if len(line1) + len(w) < 14:
            line1 += w + " "
        else:
            line2 += w + " "
    draw.text((info_x + 16, 62), line1.strip(), font=fB, fill=C_TEXT)
    if line2:
        draw.text((info_x + 16, 105), line2.strip(), font=fB, fill=C_TEXT)

    y_info = 150 if not line2 else 155
    # Ville
    draw.text((info_x + 16, y_info), f"📍 {unit.get('city', '')}", font=fN, fill=C_MUTED)
    y_info += 30
    draw.text((info_x + 16, y_info), unit.get("address", "")[:35], font=fS, fill=C_MUTED)
    y_info += 30
    draw.rectangle([info_x + 16, y_info, W - 16, y_info + 1], fill=C_ACCENT)
    y_info += 14

    # Stats
    stats = [
        ("Surface",     f"{unit.get('surface', '?')} m²"),
        ("Pièces",      f"{unit.get('rooms', '?')} pcs"),
        ("Étage",       f"Ét. {unit.get('floor', '?')}"),
        ("Appartement", f"N° {unit['unit_number']}"),
    ]
    for lbl, val in stats:
        draw.text((info_x + 16, y_info), lbl, font=fS, fill=C_MUTED)
        draw.text((info_x + 16, y_info + 18), val, font=fM, fill=C_TEXT)
        y_info += 56

    # Prix
    draw.rounded_rectangle([info_x + 10, y_info, W - 10, y_info + 66],
                            radius=12, fill=C_ACCENT)
    draw.text((info_x + 20, y_info + 8),  f"{unit.get('price', '?')} MAD", font=fB, fill="white")
    draw.text((info_x + 20, y_info + 44), "par mois", font=fS, fill="white")
    y_info += 78

    # Features (max 5)
    feats = unit.get("features", [])[:5]
    for feat in feats:
        draw.text((info_x + 16, y_info), f"• {feat[:28]}", font=fS, fill=C_MUTED)
        y_info += 24

    # Contact
    contact = unit.get("contact_phone", "")
    if contact:
        draw.rectangle([info_x + 10, H - 70, W - 10, H - 10], fill=(30, 41, 59))
        draw.text((info_x + 18, H - 58), "📱 WhatsApp", font=fS, fill=C_MUTED)
        draw.text((info_x + 18, H - 38), contact, font=fM, fill=C_ACCENT)

    # Texte sur la photo (en bas à gauche)
    draw.text((16, H - 50), res_name.upper(), font=fM, fill="white")
    draw.text((16, H - 26), f"Appt {unit['unit_number']} • {unit.get('city', '')}", font=fS, fill=C_MUTED)

    canvas.save(output_path, quality=96, optimize=True)
    return output_path

# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — GÉNÉRATION DU TEXTE (LLM Groq)
# ══════════════════════════════════════════════════════════════════════
def generate_announcement_text(unit: dict, n_images: int) -> dict:
    client   = Groq(api_key=GROQ_API_KEY)
    photos_ctx = (
        f"Le post aura {n_images} photo(s) de l'appartement."
        if n_images > 0
        else "Aucune photo disponible — mettre l'accent sur les caractéristiques."
    )

    prompt = f"""Tu es agent immobilier professionnel marocain expert en marketing digital.
Génère une annonce de location optimisée pour Facebook.

Appartement :
- Résidence : {unit.get('residence_name', unit['residence_id'])} — {unit.get('city', '')}
- Adresse : {unit.get('address', '')}
- Appartement N° {unit['unit_number']}, Étage {unit.get('floor', '?')}
- Surface : {unit.get('surface', '?')} m² — {unit.get('rooms', '?')} pièces
- Prix : {unit.get('price', 'Sur demande')} MAD/mois
- Équipements : {', '.join(unit.get('features', [])) or 'Standard'}
- Description : {unit.get('description', '')}
- Contact : {unit.get('contact_phone', '')}
- {photos_ctx}

Génère un JSON avec exactement ces 3 clés :

"post_text" : Annonce Facebook complète (fr/ar marocain mixte naturel) avec :
  • Accroche percutante ligne 1
  • Description appartement (3-4 lignes)
  • Liste équipements avec emojis
  • Prix mis en valeur
  • Call-to-action WhatsApp
  • 12-15 hashtags pertinents (#ImmobilierMaroc #LocationFes etc.)
  • 250-350 mots max

"page_title" : Titre SEO court (max 65 chars, français, accrocheur)

"meta_desc" : Description OG courte (max 160 chars, accrocheur, pour aperçu Facebook)

Retourne UNIQUEMENT le JSON valide, sans texte autour."""

    r = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.72,
        max_tokens=800,
    )
    try:
        return json.loads(r.choices[0].message.content)
    except Exception:
        raw = r.choices[0].message.content.strip()
        return {
            "post_text":  raw,
            "page_title": f"Location Appt {unit['unit_number']} — {unit.get('residence_name', '')}",
            "meta_desc":  f"Appartement {unit.get('surface', '?')}m² à {unit.get('city', '')} — {unit.get('price', '?')} MAD/mois",
        }


# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — FACEBOOK PAGE API (Création Officielle)
# ══════════════════════════════════════════════════════════════════════
class FacebookPageAPI:
    def __init__(self, page_id: str, page_token: str):
        self.page_id    = page_id
        self.page_token = page_token
        self.client     = httpx.AsyncClient(timeout=120.0)

    async def close(self):
        await self.client.aclose()

    async def verify_token(self) -> bool:
        r = await self.client.get(f"{FB_API_BASE}/{self.page_id}", params={
            "access_token": self.page_token,
            "fields": "id,name,fan_count",
        })
        data = r.json()
        if "error" in data:
            print(f"❌ Token invalide: {data['error']['message']}")
            return False
        print(f"✅ Page: {data.get('name')} ({data.get('fan_count', 0)} followers)")
        return True

    async def upload_photo(self, image_path: str) -> Optional[str]:
        try:
            with open(image_path, "rb") as f:
                data = f.read()

            # Déterminer le mime type
            ext = Path(image_path).suffix.lower()
            mime_map = {".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                        ".png": "image/png",  ".webp": "image/webp"}
            mime = mime_map.get(ext, "image/jpeg")

            r = await self.client.post(
                f"{FB_API_BASE}/{self.page_id}/photos",
                data={
                    "access_token": self.page_token,
                    "published":    "false",
                },
                files={"source": (Path(image_path).name, data, mime)},
            )
            result = r.json()
            if "error" in result:
                print(f"  ❌ Upload {Path(image_path).name}: {result['error']['message']}")
                return None
            photo_id = result.get("id")
            print(f"  ✅ Uploadé: {Path(image_path).name} → id={photo_id}")
            return photo_id

        except Exception as e:
            print(f"  ❌ Upload error {image_path}: {e}")
            return None

    async def upload_all_photos(self, image_paths: list[str]) -> list[str]:
        paths = image_paths[:10]  # Facebook limite à 10 photos par post
        tasks = [self.upload_photo(p) for p in paths]
        results = await asyncio.gather(*tasks)
        photo_ids = [r for r in results if r is not None]
        print(f"  📸 {len(photo_ids)}/{len(paths)} photos uploadées")
        return photo_ids

    async def create_multi_photo_post(
        self,
        message:    str,
        photo_ids:  list[str],
    ) -> Optional[str]:
        if not photo_ids:
            # Post texte seul
            r = await self.client.post(
                f"{FB_API_BASE}/{self.page_id}/feed",
                data={"access_token": self.page_token, "message": message},
            )
            data = r.json()
            return data.get("id")

        # Post avec photos multiples (carrousel Facebook natif)
        payload = {
            "access_token": self.page_token,
            "message":      message,
        }
        for idx, pid in enumerate(photo_ids):
            payload[f"attached_media[{idx}]"] = json.dumps({"media_fbid": pid})

        r    = await self.client.post(f"{FB_API_BASE}/{self.page_id}/feed", data=payload)
        data = r.json()

        if "error" in data:
            print(f"  ❌ Post error: {data['error']['message']}")
            return None

        post_id  = data.get("id")
        post_url = f"https://www.facebook.com/{post_id.replace('_', '/posts/')}" if post_id else ""
        print(f"  ✅ Post publié: {post_url}")
        return post_id

    async def get_post_insights(self, post_id: str) -> dict:
        r = await self.client.get(
            f"{FB_API_BASE}/{post_id}/insights",
            params={
                "access_token": self.page_token,
                "metric": "post_impressions,post_reactions_by_type_total,post_shares",
            }
        )
        return r.json()


# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 4b — PARTAGE DANS LE GROUPE (PLAYWRIGHT)
# ══════════════════════════════════════════════════════════════════════
class PlaywrightGroupSharer:
    async def _load_context(self, playwright):
        browser = await playwright.chromium.launch(
            headless=False,
            args=["--no-sandbox", "--disable-setuid-sandbox"],
        )
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 800},
        )
        if not COOKIES_FILE.exists():
            await browser.close()
            raise FileNotFoundError(
                f"Cookies introuvables : {COOKIES_FILE}\n"
                "→ Exporter les cookies Facebook via Cookie Editor → sessions/facebook-cookies.json"
            )
        with open(COOKIES_FILE) as f:
            cookies = json.load(f)
        for c in cookies:
            if "sameSite" in c:
                if c["sameSite"] == "no_restriction":
                    c["sameSite"] = "None"
                elif c["sameSite"] not in ("Strict", "Lax", "None"):
                    del c["sameSite"]
        await context.add_cookies(cookies)
        return browser, context

    async def _share_one_link(self, page, group_url: str, link: str) -> bool:
        try:
            await page.goto(group_url, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(3000)

            # Zone de saisie — plusieurs sélecteurs possibles selon la langue de l'interface
            write_selectors = [
                '//span[contains(translate(text(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "exprimez")]',
                '//span[contains(translate(text(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "write something")]',
                '//span[contains(text(), "اكتب شيئًا")]',
                '//div[@role="button" and contains(@aria-label, "Créer")]',
                '//div[@role="button" and contains(@aria-label, "Create")]',
                '//div[@data-pagelet="GroupComposer"]//div[@role="button"]'
            ]
            clicked = False
            for sel in write_selectors:
                try:
                    await page.wait_for_selector(sel, timeout=4000)
                    await page.click(sel)
                    clicked = True
                    break
                except Exception:
                    continue

            if not clicked:
                print(f"    ⚠️  Zone de saisie introuvable pour {group_url}")
                return False

            # Éditeur de texte dans la modal
            editor_sel = "//div[@role='dialog']//div[@contenteditable='true']"
            await page.wait_for_selector(editor_sel, timeout=8000)
            await page.fill(editor_sel, link)

            # Attente preview (adaptatif : 5–12s selon réseau)
            print("    ⏳ Génération du preview Facebook...")
            await page.wait_for_timeout(8000)

            # Bouton publier — sélecteurs fr + en + ar
            pub_selectors = [
                "//div[@role='dialog']//div[@aria-label='Publier']",
                "//div[@role='dialog']//div[@aria-label='Post']",
                "//div[@role='dialog']//div[@aria-label='نشر']",
                "//div[@role='dialog']//span[text()='Publier']/..",
            ]
            published = False
            for sel in pub_selectors:
                try:
                    await page.wait_for_selector(sel, timeout=4000)
                    await page.click(sel)
                    published = True
                    break
                except Exception:
                    continue

            if not published:
                print(f"    ⚠️  Bouton Publier introuvable")
                return False

            await page.wait_for_timeout(5000)
            return True

        except Exception as e:
            print(f"    ❌ Erreur : {e}")
            return False

    async def share_links(
        self,
        group_urls: list[str],    # liste de groupes (anciennement group_url unique)
        post_links: list[str],
        delay_between_groups: int = 30,
    ):
        if not post_links:
            return

        # Rétrocompatibilité : accepte une string (1 seul groupe)
        if isinstance(group_urls, str):
            group_urls = [group_urls]

        print("\n" + "="*60)
        print(f"🤖 PLAYWRIGHT : partage dans {len(group_urls)} groupe(s)")
        print("="*60)

        ok_count = 0
        async with async_playwright() as p:
            try:
                browser, context = await self._load_context(p)
            except FileNotFoundError as e:
                print(f"  ❌ {e}")
                return

            page = await context.new_page()

            for group_url in group_urls:
                print(f"\n  📤 Groupe : {group_url}")
                for link in post_links:
                    print(f"    [*] Partage : {link}")
                    success = await self._share_one_link(page, group_url, link)
                    if success:
                        print(f"    ✅ Partagé !")
                        ok_count += 1
                    await asyncio.sleep(delay_between_groups)

            await browser.close()

        print(f"\n  📊 Résultat : {ok_count}/{len(group_urls)*len(post_links)} partages réussis")


# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — LIRE LES UNITÉS VIDES DEPUIS LA DB + JSON
# ══════════════════════════════════════════════════════════════════════
async def get_empty_units(residence_id: Optional[str] = None) -> list[dict]:
    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        if residence_id:
            residences = await conn.fetch(
                "SELECT id, name, city, address, units_count FROM residences WHERE id = $1",
                residence_id
            )
        else:
            residences = await conn.fetch(
                "SELECT id, name, city, address, units_count FROM residences"
            )

        # Charger le JSON local
        units_details = {}
        if Path(UNITS_JSON).exists():
            with open(UNITS_JSON, encoding="utf-8") as f:
                jdata = json.load(f)
            for u in jdata.get("units", []):
                key = f"{u['residence_id']}_{u['unit_number']}"
                units_details[key] = u

        empty = []
        for res in residences:
            res_id   = res["id"]
            occupied = {r["unit_number"] for r in await conn.fetch(
                "SELECT unit_number FROM residents WHERE residence_id = $1", res_id
            )}

            # Liste des unités depuis le JSON
            all_nums = []
            if Path(UNITS_JSON).exists():
                with open(UNITS_JSON, encoding="utf-8") as f:
                    all_nums = [u["unit_number"] for u in json.load(f).get("units", [])
                                if u.get("residence_id") == res_id]
            if not all_nums:
                all_nums = [str(i) for i in range(1, (res["units_count"] or 0) + 1)]

            for num in all_nums:
                if num not in occupied:
                    key = f"{res_id}_{num}"
                    det = units_details.get(key, {})
                    empty.append({
                        "unit_number":    num,
                        "residence_id":   res_id,
                        "residence_name": det.get("residence_name") or res["name"],
                        "city":           det.get("city") or res["city"] or "",
                        "address":        det.get("address") or res["address"] or "",
                        "contact_phone":  det.get("contact_phone", os.getenv("CONTACT_PHONE", "")),
                        "surface":        det.get("surface", "?"),
                        "rooms":          det.get("rooms", "?"),
                        "floor":          det.get("floor", "?"),
                        "price":          det.get("price", "Sur demande"),
                        "description":    det.get("description", ""),
                        "features":       det.get("features", []),
                        "images":         det.get("images", []),
                    })
        return empty
    finally:
        await conn.close()

# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — TRACKER ANTI-DOUBLON
# ══════════════════════════════════════════════════════════════════════
class AnnouncementTracker:
    FILE = "announcement_tracker.json"
    def __init__(self):
        self.data = json.loads(Path(self.FILE).read_text()) if Path(self.FILE).exists() else {}
    def was_posted_recently(self, key: str, hours: int = 48) -> bool:
        if key not in self.data: return False
        return (datetime.now() - datetime.fromisoformat(self.data[key]["posted_at"])).total_seconds() < hours * 3600
    def mark(self, key: str, post_id: str):
        self.data[key] = {"posted_at": datetime.now().isoformat(), "post_id": post_id}
        Path(self.FILE).write_text(json.dumps(self.data, indent=2, default=str))

# ══════════════════════════════════════════════════════════════════════
# ÉTAPE 7 — AGENT PRINCIPAL
# ══════════════════════════════════════════════════════════════════════
async def run_announcement_agent(residence_id: Optional[str] = None):
    print(f"\n{'='*65}")
    print(f"  🤖 AGENT HYBRIDE (API PAGE + PLAYWRIGHT GROUPE) — {datetime.now().strftime('%d/%m/%Y %H:%M')}")
    print(f"{'='*65}\n")

    fb = FacebookPageAPI(FB_PAGE_ID, FB_PAGE_ACCESS_TOKEN)
    tracker = AnnouncementTracker()

    if not await fb.verify_token():
        await fb.close()
        return

    empty = await get_empty_units(residence_id)
    if not empty:
        print("✅ Aucune unité vide.")
        await fb.close()
        return

    results = []

    # ── 1. PUBLICATION API SUR LA PAGE ──
    for unit in empty:
        unit_key = f"{unit['residence_id']}_{unit['unit_number']}"
        if tracker.was_posted_recently(unit_key):
            continue

        print(f"\n  📝 Traitement : {unit_key}")
        images = get_unit_images(unit, max_images=5)
        
        if not images:
            fallback = str(OUTPUT_DIR / f"{unit_key}_poster.jpg")
            create_fallback_poster(unit, fallback)
            images = [fallback]
            
        texts = generate_announcement_text(unit, len(images))
        photo_ids = await fb.upload_all_photos(images)
        await asyncio.sleep(2)
        
        post_id = await fb.create_multi_photo_post(texts["post_text"], photo_ids)
        if post_id:
            tracker.mark(unit_key, post_id)
            results.append({"unit": unit_key, "post_id": post_id, "status": "ok"})
            print(f"  ✅ Publié sur la Page !")
        await asyncio.sleep(5)

    await fb.close()

    # ── 2. PARTAGE DANS LE GROUPE VIA PLAYWRIGHT ──
    post_links_to_share = []
    for r in results:
        if r.get("status") == "ok":
            # Extraire le vrai ID de post Facebook (souvent formaté en IDPAGE_IDPOST)
            real_post_id = r["post_id"].split('_')[-1]
            link = f"https://www.facebook.com/{FB_PAGE_ID}/posts/{real_post_id}"
            post_links_to_share.append(link)

    if post_links_to_share:
        # Support multi-groupes : FB_GROUP_URLS="url1,url2" ou FB_GROUP_URL (rétrocompat)
        group_urls_env = os.getenv("FB_GROUP_URLS", "")
        if group_urls_env:
            group_urls = [u.strip() for u in group_urls_env.split(",") if u.strip()]
        else:
            group_urls = [FB_GROUP_URL] if FB_GROUP_URL else []

        if group_urls:
            sharer = PlaywrightGroupSharer()
            await sharer.share_links(group_urls, post_links_to_share, delay_between_groups=30)
        else:
            print("  ⚠️  Aucun groupe configuré — définir FB_GROUP_URL ou FB_GROUP_URLS dans .env")

# ══════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════
async def main():
    import sys
    args = sys.argv[1:]

    if "--verify" in args:
        fb = FacebookPageAPI(FB_PAGE_ID, FB_PAGE_ACCESS_TOKEN)
        await fb.verify_token()
        await fb.close()

    elif "--scan" in args:
        # Affiche les images disponibles par unité
        import asyncio
        empty = await get_empty_units()
        print(f"\n📸 Scan des images ({len(empty)} unités vides) :")
        total_imgs = 0
        for unit in empty:
            imgs = get_unit_images(unit, max_images=10)
            total_imgs += len(imgs)
            unit_key = f"{unit['residence_id']}_{unit['unit_number']}"
            print(f"  {unit_key}: {len(imgs)} image(s)")
            for img in imgs:
                print(f"    • {img}")
        print(f"\nTotal : {total_imgs} images pour {len(empty)} unités")

    elif "--once" in args:
        res_id = args[args.index("--once") + 1] if len(args) > args.index("--once") + 1 and not args[args.index("--once") + 1].startswith("--") else None
        await run_announcement_agent(res_id)

    else:
        scheduler = AsyncIOScheduler(timezone="Africa/Casablanca")
        scheduler.add_job(run_announcement_agent, trigger="interval", hours=48)
        scheduler.start()
        print("⏰ Scheduler démarré — exécution toutes les 48h")
        try:
            while True: await asyncio.sleep(3600)
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    asyncio.run(main())