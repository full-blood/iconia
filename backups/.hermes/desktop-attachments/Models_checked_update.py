import os
import sys
import time
import json
import sqlite3
from pathlib import Path
from html import escape
from collections import defaultdict
from datetime import datetime

# On remonte la définition du chemin JSON pour pouvoir le lire dès le début
output_db = r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\library.db"

def get_next_version(db_path):
    default_version = "1.0.00"
    if not os.path.exists(db_path):
        return default_version
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM Metadata WHERE key = 'version'")
        row = cursor.fetchone()
        conn.close()
        
        if row:
            current_version = row[0]
            parts = current_version.split(".")
            if len(parts) == 3:
                last_part = str(int(parts[2]) + 1).zfill(2)
                return f"{parts[0]}.{parts[1]}.{last_part}"
    except Exception as e:
        print(f"<!> Impossible de lire l'ancienne version, redémarrage à {default_version} ({e})")
        
    return default_version

VERSION = get_next_version(output_db) # On passe maintenant output_db au lieu de output_json
print(f"Génération de la version : {VERSION}")

categories = defaultdict(set)

test_mode = "--limit" in sys.argv
max_found = 3 if test_mode else None
for arg in sys.argv:
    if arg.startswith("--") and arg[2:].isdigit():
        max_found = int(arg[2:])
        print(f"Limite : {max_found}")
        break

start_time = time.time()

base_dir    = r"\\CGLibrary\CgLibrary\3-Models"
output_html = r"\\CGLibrary\CgLibrary\3-Models\Library.html"

# La variable output_json a été remontée plus haut
image_exts  = [".jpg", ".jpeg", ".png"]
thumbnails  = []
missing     = []
assets      = []
found       = 0

# ── Initialisation de la BDD ──────────────────────────────────────────────────
conn = sqlite3.connect(output_db)
cursor = conn.cursor()

# Création des tables nécessaires si elles n'existent pas
cursor.execute('''
    CREATE TABLE IF NOT EXISTS Users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE
    )
''')

cursor.execute('''
    CREATE TABLE IF NOT EXISTS Favorites (
        user_id INTEGER,
        model_name TEXT,
        PRIMARY KEY (user_id, model_name),
        FOREIGN KEY (user_id) REFERENCES Users(id)
    )
''')

# On supprime la table pour forcer l'ajout de la nouvelle colonne
#cursor.execute('DROP TABLE IF EXISTS Models')

cursor.execute('''
    CREATE TABLE IF NOT EXISTS Models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        max_path TEXT,
        image_path TEXT,
        txt_path TEXT,
        folder_path TEXT,
        category TEXT,
        subcategory TEXT,
        keywords TEXT,
        proxy_suffix TEXT,
        file_date INTEGER
    )
''')
    
cursor.execute('''
    CREATE TABLE IF NOT EXISTS Metadata (
        key TEXT PRIMARY KEY,
        value TEXT
    )
''')

cursor.execute('''
    CREATE TABLE IF NOT EXISTS MissingFiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        missing_type TEXT,
        folder_path TEXT
    )
''')

# ──────────────────────────────────────────────────────────────────────────────



# ── DÉTECTION DU MODE DE LANCEMENT ────────────────────────────────────────────
html_only = "--html-only" in sys.argv
thumbnails = [] # On initialise la liste ici pour qu'elle soit dispo partout

if not html_only:
    print("Mode SCAN COMPLET démarré...")
    # On vide les tables dynamiques avant le nouveau scan
    cursor.execute('DELETE FROM Models')
    cursor.execute('DELETE FROM MissingFiles')
    conn.commit()

    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if "_CHECKED_OK" in file:
                print(f"Fichier CHECKED_OK trouve : {file}")
                base_name = file.replace("_CHECKED_OK.txt", "").replace(".max", "")
                max_file  = Path(root) / f"{base_name}.max"

                if not max_file.exists():
                    print(f"<!> Fichier .max manquant : {max_file}")
                    cursor.execute("INSERT INTO MissingFiles (name, missing_type, folder_path) VALUES (?, ?, ?)", 
                                   (base_name, "max", str(Path(root)).replace("\\", "/")))
                    continue

                image_file = None
                for ext in image_exts:
                    test_image = Path(root) / f"{base_name}{ext}"
                    if test_image.exists():
                        image_file = test_image
                        break

                if not image_file:
                    print(f"Pas d'image trouvee dans {root}")
                    cursor.execute("INSERT INTO MissingFiles (name, missing_type, folder_path) VALUES (?, ?, ?)", 
                                   (base_name, "image", str(Path(root)).replace("\\", "/")))
                    continue

                txt_file    = Path(root) / f"{base_name}.max_CHECKED_OK.txt"
                txt_preview = ""

                if txt_file.exists():
                    try:
                        with open(txt_file, "r", encoding="utf-8-sig") as f:
                            txt_preview = f.read().strip()
                    except Exception as e:
                        txt_preview = f"Erreur de lecture : {e}"

                main_cat         = None
                category_attr    = ".None"
                subcategory_attr = "none"
                keywords_list    = []

                for line in txt_preview.splitlines():
                    line = line.strip()
                    if line.startswith("-") and not line.startswith("--"):
                        main_cat = line[1:].strip().lower().title()
                        category_attr = main_cat
                    elif line.startswith("--") and main_cat:
                        subcat = line[2:].strip().lower().title()
                        subcategory_attr = subcat
                    elif line:
                        keywords_list.append(line)

                max_file_path   = str(max_file).replace("\\", "/")
                folder_path     = str(Path(root)).replace("\\", "/")
                txt_file_path   = str(txt_file).replace("\\", "/")
                image_file_path = str(image_file).replace("\\", "/")

                # --- Détection du Proxy ---
                # --- NOUVEAU : Détection du Proxy multi-formats ---
                proxy_suffix = ""
                # On teste les variations les plus courantes
                suffixes_a_tester = ["_cproxy", "_proxy", "_Cproxy", "_Proxy", "-proxy", "-cproxy"]
                
                for suffix in suffixes_a_tester:
                    if (Path(root) / f"{base_name}{suffix}.max").exists():
                        proxy_suffix = suffix
                        break
                # --------------------------------------------------

                file_date = int(os.path.getctime(txt_file)) if txt_file.exists() else 0
                
                keywords_str = ",".join(keywords_list)
                
                # Mise à jour de la requête SQL avec proxy_suffix
                cursor.execute('''
                    INSERT INTO Models (name, max_path, image_path, txt_path, folder_path, category, subcategory, keywords, proxy_suffix, file_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (base_name, max_file_path, image_file_path, txt_file_path, folder_path, category_attr, subcategory_attr, keywords_str, proxy_suffix, file_date))
                
                found += 1

                if max_found and found >= max_found:
                    print(f"Limite de {max_found} fichiers atteinte.")
                    break
        if max_found and found >= max_found:
            break

    # Enregistrement des métadonnées une fois le scan terminé
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M")
    cursor.execute("REPLACE INTO Metadata (key, value) VALUES ('generated_at', ?)", (generated_at,))
    cursor.execute("REPLACE INTO Metadata (key, value) VALUES ('version', ?)", (VERSION,))
    cursor.execute("REPLACE INTO Metadata (key, value) VALUES ('count', ?)", (str(found),))
    
    conn.commit()
    print("Scan complet terminé et enregistré dans SQLite.")

else:
    print("Mode HTML-ONLY : Régénération instantanée depuis SQLite...")


# ── GÉNÉRATION DES MINIATURES DEPUIS LA BDD (Rapide !) ────────────────────────
print("Création du HTML...")
# On ajoute file_date dans le SELECT
cursor.execute("SELECT name, max_path, image_path, txt_path, folder_path, category, subcategory, keywords, proxy_suffix, file_date FROM Models")
for row in cursor.fetchall():
    base_name, max_file_path, image_file_path, txt_file_path, folder_path, category_attr, subcategory_attr, keywords_str, proxy_suffix, file_date = row
    
    search_text = f"{base_name} {category_attr} {subcategory_attr} {keywords_str}".lower()

    # Le HTML de l'icône proxy
    proxy_html = '<div class="proxy-icon" onclick="toggleProxy(event, this)" title="Utiliser la version Proxy">PROXY</div>' if proxy_suffix else ''

    thumbnails.append(
        '<div class="thumbnail"'
        f' data-search="{escape(search_text)}"'
        f' data-category="{escape(category_attr)}"'
        f' data-subcategory="{escape(subcategory_attr)}"'
        f' data-txt-path="{escape(txt_file_path)}"'
        f' data-basename="{escape(base_name)}"'
        f' data-max-path="{escape(max_file_path)}"'
        f' data-folder-path="{escape(folder_path)}"'
        f' data-proxy-suffix="{escape(proxy_suffix)}"'
        f' data-date="{file_date}"' # <-- L'ATTRIBUT DE DATE EST ICI
        ' style="display:inline-block;margin:10px;text-align:center;width:220px;">'
        '<div class="heart-icon">&#x2764;</div>'
        f'{proxy_html}'
        f'<img src="{escape(image_file_path)}" title="{escape(base_name)}"'
        ' loading="lazy"'
        ' style="width:220px;height:220px;object-fit:cover;cursor:pointer;"'
        ' onclick="handleImgClick(this.parentElement)"'
        '><br></div>'
    )

# On valide et on ferme la base de données. On récupère les métadonnées pour l'affichage dans le HTML
cursor.execute("SELECT key, value FROM Metadata")
meta_rows = cursor.fetchall()
meta_dict = {row[0]: row[1] for row in meta_rows}

generated_at = meta_dict.get('generated_at', 'Inconnue')
found = int(meta_dict.get('count', len(thumbnails)))
# ---------------------------------------------------------------------------

# On valide et on ferme la base de données une fois qu'on a tout lu
conn.commit()
conn.close()
print("Opérations SQLite terminées.")

# ── PRÉPARATION DU HTML FINAL ─────────────────────────────────────────────────
thumbnails_html = "\n".join(thumbnails) if thumbnails else "<p>Aucune miniature trouvée.</p>"

# ── JS ────────────────────────────────────────────────────────────────────────
JS = r"""
const API_BASE  = "http://10.13.54.151:8000";
const API_TOKEN = "RENDER_TEAM_2024";

let activeCategory    = null;
let activeSubcategory = null;
let clickTimer        = null;
let currentUser       = localStorage.getItem("currentUser") || null;
let activeFavMode     = false;

/* ── GESTION DES MOTS-CLÉS (Datalist & Inputs dynamiques) ── */
let allKeywords = [];

async function loadAllKeywords() {
    try {
        const r = await fetch(API_BASE + "/api/keywords");
        allKeywords = await r.json();
        const dl = document.getElementById("allKeywordsList");
        // Remplir la datalist native
        dl.innerHTML = allKeywords.map(k => `<option value="${escapeHtml(k)}">`).join("");
    } catch(e) { console.error("Erreur mots-clés", e); }
}

function addKwInputRow(value = "") {
    const container = document.getElementById("kwInputsContainer");
    const row = document.createElement("div");
    row.style.cssText = "display:flex; gap:5px; margin-bottom:5px;";
    row.innerHTML = `
        <input type="text" class="kw-field single-kw" value="${escapeHtml(value)}" list="allKeywordsList" style="margin-bottom:0; flex:1;" placeholder="Mot-clé...">
        <button onclick="this.parentElement.remove()" style="background:#e74c3c; color:white; border:none; border-radius:4px; width:30px; cursor:pointer; font-weight:bold;">X</button>
    `;
    container.appendChild(row);
}

/* ── AUTO-COMPLÉTION DES KEYWORDS ─────────────────────── */
function onKwInput() {
    const ta = document.getElementById("kwKeywords");
    const list = document.getElementById("kwAutocomplete");
    const val = ta.value;
    
    // Trouver où se trouve le curseur pour savoir quelle ligne on édite
    const cursorPos = ta.selectionStart;
    const textBefore = val.substring(0, cursorPos);
    const linesBefore = textBefore.split('\n');
    const currentLineIdx = linesBefore.length - 1;
    const currentLineText = linesBefore[currentLineIdx];
    const searchStr = currentLineText.trim().toLowerCase();

    if (!searchStr) { list.style.display = "none"; return; }

    // Chercher les correspondances
    const matches = allKeywords.filter(k => k.toLowerCase().includes(searchStr) && k.toLowerCase() !== searchStr);
    if (matches.length === 0) { list.style.display = "none"; return; }

    // Construire le menu
    let html = "";
    matches.forEach(match => {
        html += `<div onclick="selectKw('${match.replace(/'/g, "\\'")}', ${currentLineIdx})">${match}</div>`;
    });
    list.innerHTML = html;
    list.style.display = "block";
}

function selectKw(kw, lineIdx) {
    const ta = document.getElementById("kwKeywords");
    const lines = ta.value.split('\n');
    lines[lineIdx] = kw; // On remplace uniquement la ligne en cours d'édition
    ta.value = lines.join('\n') + '\n';
    document.getElementById("kwAutocomplete").style.display = "none";
    ta.focus();
}

// Pour cacher le menu si on clique ailleurs
document.addEventListener("click", function(e) {
    if (e.target.id !== "kwKeywords") {
        const list = document.getElementById("kwAutocomplete");
        if(list) list.style.display = "none";
    }
});

/* ── INITIALISATION / CONNEXION ───────────────────────── */
async function checkConnection() {
    const dot    = document.getElementById("connDot");
    const tip    = document.getElementById("connTip");
    const navDot = document.getElementById("navConnDot");
    const navTip = document.getElementById("navConnTip");
    try {
        const r  = await fetch(API_BASE + "/", {signal: AbortSignal.timeout(3000)});
        const ok = r.ok;
        dot.style.background = ok ? "#27ae60" : "#e74c3c";
        tip.textContent      = ok ? "RENDER-01 connecté" : "RENDER-01 déconnecté";
        navDot.style.display = ok ? "none" : "inline-block";
        navTip.style.display = ok ? "none" : "inline";
        navTip.textContent   = ok ? "" : "Serveur déconnecté !";
    } catch(e) {
        dot.style.background    = "#e74c3c";
        tip.textContent         = "RENDER-01 déconnecté";
        navDot.style.display    = "inline-block";
        navTip.style.display    = "inline";
        navTip.textContent      = "Serveur déconnecté !";
    }
}

window.addEventListener("DOMContentLoaded", () => {
    checkConnection();
    setInterval(checkConnection, 30000);
    updateUserNavUI();
    if (currentUser) loadFavorites();
    loadCategories();
});

function toggleProxy(event, el) {
    event.stopPropagation(); // Empêche le clic de se propager à l'image en dessous
    el.classList.toggle("active");
    if (el.classList.contains("active")) {
        showNotification("&#x2699; Mode Proxy activé !", 1500);
    }
}

/* ── GÉNÉRATION DYNAMIQUE DU MENU ─────────────────────── */
function escapeHtml(text) {
    return (text || "").toString().replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

async function loadCategories() {
    const sidebar = document.getElementById("sidebar");
    try {
        const r = await fetch(API_BASE + "/api/categories");
        const data = await r.json();
        
        let html = "";
        const sortedCats = Object.keys(data).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
        
        for (const cat of sortedCats) {
            if (cat === ".None" && sortedCats.length > 1) continue;

            // CORRECTION : On applique la classe active directement si c'est la catégorie en cours
            const isCatActive = cat === activeCategory ? " active" : "";

            html += `<div class="sidebar-group">
                <div class="sidebar-category${isCatActive}" data-cat="${escapeHtml(cat)}" onclick="sidebarCatClick(this)">
                    <span class="arrow" onclick="event.stopPropagation();toggleCategory(this)">&#9660;</span>
                     ${escapeHtml(cat)}
                </div>
                <div class="subcategory-container">`;

            for (const subcat of data[cat]) {
                if (cat === "Vegetation" && subcat === "MaxTree") {
                    html += `<div class="sidebar-subcategory" onclick="window.open('file:///L:/3-Models/Vegetation/MaxTree/maxtree_library.html','_blank')">${escapeHtml(subcat)}</div>`;
                } else {
                    // CORRECTION : On applique la classe active si c'est la sous-catégorie en cours
                    const isSubActive = (cat === activeCategory && subcat === activeSubcategory) ? " active" : "";
                    html += `<div class="sidebar-subcategory${isSubActive}" data-cat="${escapeHtml(cat)}" data-subcat="${escapeHtml(subcat)}" onclick="sidebarSubcatClick(this)">${escapeHtml(subcat)}</div>`;
                }
            }
            html += `</div></div>`;
        }
        sidebar.innerHTML = html;
        
        // CORRECTION : On rafraîchit les miniatures avec les filtres existants, SANS remettre la recherche à zéro
        filterThumbnails();
        
    } catch(e) {
        sidebar.innerHTML = '<div style="padding:15px;color:#e74c3c;font-size:13px;">Erreur de chargement du menu.</div>';
    }
}

/* ── INTERACTION CLIC ─────────────────────────────────── */
function handleImgClick(div) {
    document.querySelectorAll(".thumbnail.last-clicked").forEach(el => el.classList.remove("last-clicked"));
    div.classList.add("last-clicked");
    const maxPath    = div.dataset.maxPath;
    const folderPath = div.dataset.folderPath;
    const basename   = div.dataset.basename;
    if (clickTimer) {
        clearTimeout(clickTimer);
        clickTimer = null;
        doCopy(folderPath, basename, div, "dossier");
    } else {
        clickTimer = setTimeout(() => {
            clickTimer = null;
            doCopy(maxPath, basename, div, "max");
        }, 220);
    }
}

function doCopy(path, basename, div, type) {
    let winPath = path
        .replace(/^\/\/CGLibrary\/CgLibrary\/3-Models/, "L:\\3-Models")
        .replace(/^\\\\CGLibrary\\CgLibrary\\3-Models/, "L:\\3-Models")
        .replace(/\//g, "\\");
    
    let isProxy = false;
    let finalBasename = basename;

    // Si on copie le .max, on vérifie si l'icône proxy est active
    if (type === "max") {
        const prx = div.querySelector(".proxy-icon");
        const pSuffix = div.dataset.proxySuffix; // <-- On récupère le suffixe exact (_proxy, _cproxy...)
        
        if (prx && prx.classList.contains("active") && pSuffix) {
            winPath = winPath.replace(".max", pSuffix + ".max");
            finalBasename = basename + pSuffix;
            isProxy = true;
        }
    }

    navigator.clipboard.writeText(winPath).then(() => {
        const label = type === "max" ? (isProxy ? "Chemin PROXY copié !" : "Chemin .max copié !") : "Dossier copié !";
        document.getElementById("thumbnailInfo").innerHTML =
            '<span style="color:black;font-weight:600;">' + finalBasename + '</span>' +
            '  <span style="color:silver;font-size:11px;">' + winPath + '</span>';
        document.getElementById("thumbnailInfo").style.backgroundColor = "#eee";
        showNotification("&#10003; " + label);
        highlightSidebar(div);
    }).catch(() => alert("Impossible de copier le chemin."));
}

function highlightSidebar(div) {
    document.querySelectorAll(".sidebar-category").forEach(el => el.classList.remove("active"));
    document.querySelectorAll(".sidebar-subcategory").forEach(el => el.classList.remove("active"));
    const cat    = div.dataset.category;
    const subcat = div.dataset.subcategory;
    document.querySelectorAll(".sidebar-category").forEach(el => {
        if (el.dataset.cat === cat) el.classList.add("active");
    });
    document.querySelectorAll(".sidebar-subcategory").forEach(el => {
        if (el.dataset.subcat === subcat) el.classList.add("active");
    });
}

let notifTimer = null;
function showNotification(msg, duration = 2000) {
    const n = document.getElementById("copyNotification");
    n.innerHTML = msg;
    n.classList.add("show");
    if (notifTimer) clearTimeout(notifTimer);
    notifTimer = setTimeout(() => n.classList.remove("show"), duration);
}

/* ── GESTION DES FAVORIS ──────────────────────────────── */
async function loadFavorites() {
    if (!currentUser) return;
    try {
        const r = await fetch(API_BASE + "/api/favorites/" + encodeURIComponent(currentUser));
        const favs = await r.json();
        document.querySelectorAll(".thumbnail").forEach(div => {
            if (favs.includes(div.dataset.basename)) {
                div.classList.add("is-favorite");
            } else {
                div.classList.remove("is-favorite");
            }
        });
    } catch(e) { console.error("Erreur chargement favoris", e); }
}

async function toggleFavoriteFromBtn() {
    if (!currentUser) {
        alert("Veuillez d'abord sélectionner ou créer un USER.");
        openUserModal();
        return;
    }
    const div = document.querySelector(".thumbnail.last-clicked");
    if (!div) {
        alert("Cliquez d'abord sur un asset pour le sélectionner.");
        return;
    }
    const basename = div.dataset.basename;
    try {
        const r = await fetch(API_BASE + "/api/favorites/toggle", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({username: currentUser, model_name: basename})
        });
        
        // --- NOUVEAU : On lit l'erreur renvoyée par le serveur Python ---
        if (!r.ok) {
            const errData = await r.json();
            alert("Erreur : " + errData.detail);
            
            // Si l'utilisateur a été supprimé de la BDD, on nettoie le navigateur
            if (errData.detail === "Utilisateur introuvable") {
                currentUser = null;
                localStorage.removeItem("currentUser");
                updateUserNavUI();
                openUserModal();
            }
            return;
        }
        // -----------------------------------------------------------------

        const data = await r.json();
        if (data.status === "ok") {
            if (data.action === "added") {
                div.classList.add("is-favorite");
                showNotification("❤ Ajouté aux favoris", 2000);
            } else {
                div.classList.remove("is-favorite");
                showNotification(
                    `💔 Supprimé des favoris <span onclick="undoFavoriteRemove('${basename.replace(/'/g, "\\'")}')" style="margin-left:15px; text-decoration:underline; cursor:pointer; color:#f1c40f;">Annuler</span>`, 
                    4000
                );
                if (activeFavMode) filterThumbnails();
            }
        }
    } catch(e) { alert("Erreur réseau impossible de joindre le serveur."); }
}

async function undoFavoriteRemove(basename) {
    if (!currentUser) return;
    try {
        const r = await fetch(API_BASE + "/api/favorites/toggle", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({username: currentUser, model_name: basename})
        });
        const data = await r.json();
        if (data.status === "ok" && data.action === "added") {
            // On retrouve la miniature et on lui remet la classe favoris
            document.querySelectorAll(".thumbnail").forEach(div => {
                if (div.dataset.basename === basename) {
                    div.classList.add("is-favorite");
                }
            });
            showNotification("❤ Favori restauré !", 2000);
            // Si on était en mode "Favoris seulement", il faut la réafficher
            if (activeFavMode) filterThumbnails();
        }
    } catch(e) { alert("Erreur serveur lors de l'annulation"); }
}

function toggleFavMode() {
    activeFavMode = !activeFavMode;
    const btn = document.getElementById("navFavModeBtn");
    btn.style.fontWeight = activeFavMode ? "700" : "300";
    btn.style.color = activeFavMode ? "#222" : "#888";
    filterThumbnails();
}

/* ── GESTION DES UTILISATEURS (MODAL) ─────────────────── */
function openUserModal() {
    document.getElementById("userModal").classList.add("open");
    loadUserList();
}
function closeUserModal() { document.getElementById("userModal").classList.remove("open"); }

async function loadUserList() {
    const listDiv = document.getElementById("userListContainer");
    listDiv.innerHTML = "Chargement...";
    try {
        const r = await fetch(API_BASE + "/api/users");
        const users = await r.json();
        if(users.length === 0) {
            listDiv.innerHTML = "<p style='color:#aaa;font-size:12px;'>Aucun utilisateur trouvé.</p>";
            return;
        }
        let html = "";
        users.forEach(u => {
            const isCurrent = u === currentUser ? "<b>(Actif)</b> " : "";
            html += `<div class="user-item">
                <span onclick="selectUser('${u}')">${isCurrent}${u}</span>
                <div class="user-actions">
                    <button class="user-action-btn" onclick="renameUserPrompt('${u}')">✏</button>
                    <button class="user-action-btn" onclick="deleteUserAction('${u}')">🗑</button>
                </div>
            </div>`;
        });
        listDiv.innerHTML = html;
    } catch(e) { listDiv.innerHTML = "Erreur de chargement"; }
}

async function createUserAction() {
    const input = document.getElementById("newUsernameInput");
    const username = input.value.trim();
    if (!username) return;
    try {
        const r = await fetch(API_BASE + "/api/users/create", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({username: username})
        });
        if(r.ok) {
            input.value = "";
            loadUserList();
        } else {
            const err = await r.json();
            alert(err.detail);
        }
    } catch(e) { alert("Erreur de connexion"); }
}

function selectUser(username) {
    currentUser = username;
    localStorage.setItem("currentUser", username);
    updateUserNavUI();
    loadFavorites();
    closeUserModal();
    if (activeFavMode) filterThumbnails();
}

function updateUserNavUI() {
    const btn = document.getElementById("navUserBtn");
    const favBtn = document.getElementById("navFavModeBtn");
    const favSep = document.getElementById("navFavSep");
    if (currentUser) {
        btn.textContent = currentUser.toUpperCase();
        favBtn.style.display = "inline";
        if(favSep) favSep.style.display = "inline";
    } else {
        btn.textContent = "USER";
        favBtn.style.display = "none";
        if(favSep) favSep.style.display = "none";
    }
}

async function renameUserPrompt(oldName) {
    const newName = prompt("Entrez le nouveau nom pour " + oldName + " :", oldName);
    if (!newName || newName.trim() === oldName) return;
    try {
        const r = await fetch(API_BASE + "/api/users/rename", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({username: oldName, new_username: newName.trim()})
        });
        if (r.ok) {
            if (currentUser === oldName) {
                currentUser = newName.trim();
                localStorage.setItem("currentUser", currentUser);
                updateUserNavUI();
            }
            loadUserList();
        }
    } catch(e) {}
}

async function deleteUserAction(username) {
    if (!confirm("Supprimer l'utilisateur " + username + " ainsi que tous ses favoris ?")) return;
    try {
        const r = await fetch(API_BASE + "/api/users/delete", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({username: username})
        });
        if (r.ok) {
            if (currentUser === username) {
                currentUser = null;
                localStorage.removeItem("currentUser");
                document.querySelectorAll(".thumbnail").forEach(div => div.classList.remove("is-favorite"));
                updateUserNavUI();
            }
            loadUserList();
        }
    } catch(e) {}
}

/* ── FILTRES & RECHERCHE AVANCÉE ──────────────────────── */
let advExcludeCat   = "";
let advExcludeSub   = "";
let advExcludeWords = "";
let advReqProxy     = false;
let advFavFirst     = false;
let advSortOrder    = "date_desc";

function openAdvSearch() {
    document.getElementById("advSearchModal").classList.add("open");
    const select = document.getElementById("advExcludeSelect");
    
    // Remplir avec les catégories ET sous-catégories
    let html = '<option value="">-- Aucune exclusion --</option>';
    document.querySelectorAll('.sidebar-category').forEach(catEl => {
        const cat = catEl.dataset.cat;
        if(cat && cat !== '.None') {
            html += `<option value="${escapeHtml(cat)}|">${escapeHtml(cat)} (Tout)</option>`;
            const subContainer = catEl.nextElementSibling;
            if(subContainer) {
                subContainer.querySelectorAll('.sidebar-subcategory').forEach(subEl => {
                    const sub = subEl.dataset.subcat;
                    if(sub && sub !== 'none') {
                        html += `<option value="${escapeHtml(cat)}|${escapeHtml(sub)}">&nbsp;&nbsp;↳ ${escapeHtml(sub)}</option>`;
                    }
                });
            }
        }
    });
    select.innerHTML = html;
    
    if (advExcludeCat) {
        select.value = advExcludeCat + "|" + advExcludeSub;
    } else {
        select.value = "";
    }
}
function closeAdvSearch() { document.getElementById("advSearchModal").classList.remove("open"); }

// --- Fonction de réinitialisation ---
function resetAdvSearch() {
    // 1. On vide les variables
    advExcludeCat   = "";
    advExcludeSub   = "";
    advExcludeWords = "";
    advReqProxy     = false;
    advFavFirst     = false;
    advSortOrder    = "date_desc";

    // 2. On remet l'interface à zéro
    document.getElementById("advExcludeSelect").value = "";
    document.getElementById("advExcludeWords").value  = "";
    document.getElementById("advProxyCheck").checked  = false;
    document.getElementById("advFavFirstCheck").checked = false;
    document.getElementById("advSortSelect").value    = "date_desc";

    // 3. On ferme et on applique
    closeAdvSearch();
    filterThumbnails();
}

function applyAdvSearch() {
    const val = document.getElementById("advExcludeSelect").value;
    if(val) {
        const parts = val.split('|');
        advExcludeCat = parts[0];
        advExcludeSub = parts[1] || "";
    } else {
        advExcludeCat = ""; advExcludeSub = "";
    }
    
    advExcludeWords = document.getElementById("advExcludeWords").value.toLowerCase();
    advReqProxy     = document.getElementById("advProxyCheck").checked;
    advFavFirst     = document.getElementById("advFavFirstCheck").checked;
    advSortOrder    = document.getElementById("advSortSelect").value;
    
    closeAdvSearch();
    filterThumbnails();
}

function filterThumbnails() {
    document.getElementById("thumbnailInfo").textContent = "";
    document.getElementById("thumbnailInfo").style.backgroundColor = "#fcfcfc";
    const input = document.getElementById("searchInput").value.toLowerCase();
    const excludeArray = advExcludeWords.split(',').map(w => w.trim()).filter(w => w);
    
    let visibleThumbs = [];
    const container = document.getElementById("thumbnailsContainer");

    document.querySelectorAll(".thumbnail").forEach(div => {
        const textMatch = div.dataset.search.includes(input);
        const catMatch  = !activeCategory    || div.dataset.category    === activeCategory;
        const subMatch  = !activeSubcategory || div.dataset.subcategory === activeSubcategory;
        const favMatch  = !activeFavMode     || div.classList.contains("is-favorite");
        
        // Exclusions Catégories
        let excludeMatch = true;
        if (advExcludeCat) {
            if (advExcludeSub) {
                if (div.dataset.category === advExcludeCat && div.dataset.subcategory === advExcludeSub) excludeMatch = false;
            } else {
                if (div.dataset.category === advExcludeCat) excludeMatch = false;
            }
        }
        
        // Exclusion Mots
        for(let w of excludeArray) {
            if (div.dataset.search.includes(w)) { excludeMatch = false; break; }
        }

        const proxyMatch = !advReqProxy || !!div.dataset.proxySuffix;

        if (textMatch && catMatch && subMatch && favMatch && excludeMatch && proxyMatch) {
            div.style.display = "inline-block";
            visibleThumbs.push(div);
        } else {
            div.style.display = "none";
        }
    });

    // Système de Tri (Favoris + Date + Alpha)
    visibleThumbs.sort((a, b) => {
        if (advFavFirst) {
            const aFav = a.classList.contains("is-favorite");
            const bFav = b.classList.contains("is-favorite");
            if (aFav && !bFav) return -1;
            if (!aFav && bFav) return 1;
        }
        
        if (advSortOrder === "date_desc") {
            return parseInt(b.dataset.date || 0) - parseInt(a.dataset.date || 0);
        } else if (advSortOrder === "date_asc") {
            return parseInt(a.dataset.date || 0) - parseInt(b.dataset.date || 0);
        } else {
            const nameA = a.dataset.basename.toLowerCase();
            const nameB = b.dataset.basename.toLowerCase();
            return advSortOrder === "az" ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
        }
    });

    // Ré-ordonner dans le DOM
    visibleThumbs.forEach(div => container.appendChild(div));
}

function sidebarCatClick(el) { selectCategory(el.dataset.cat); }
function sidebarSubcatClick(el) {
    selectCategory(el.dataset.cat);
    selectSubcategory(el.dataset.subcat);
}
function selectCategory(cat) {
    activeCategory    = cat;
    activeSubcategory = null;
    document.getElementById("searchInput").value = "";
    document.querySelectorAll(".sidebar-category, .sidebar-subcategory").forEach(el => el.classList.remove("active"));
    document.querySelectorAll(".sidebar-category").forEach(el => {
        if (el.dataset.cat === cat) el.classList.add("active");
    });
    filterThumbnails();
}
function selectSubcategory(subcat) {
    activeSubcategory = subcat;
    document.querySelectorAll(".sidebar-subcategory").forEach(el => {
        el.classList.toggle("active", el.dataset.subcat === subcat);
    });
    filterThumbnails();
}
function toggleCategory(span) {
    const container = span.closest(".sidebar-group").querySelector(".subcategory-container");
    if (!container) return;
    const hidden = container.style.display === "none";
    container.style.display = hidden ? "block" : "none";
    span.innerHTML = hidden ? "&#9660;" : "&#9654;";
}
function setSearch(value) {
    activeCategory    = null;
    activeSubcategory = null;
    document.querySelectorAll(".sidebar-category, .sidebar-subcategory").forEach(el => el.classList.remove("active"));
    filterThumbnails();
}
function clearSearch() {
    document.getElementById("searchInput").value = "";
    activeCategory    = null;
    activeSubcategory = null;
    document.querySelectorAll(".sidebar-category, .sidebar-subcategory").forEach(el => el.classList.remove("active"));
    filterThumbnails();
}

/* ── SETTINGS MODAL ───────────────────────────── */
function openSettings() {
    document.getElementById("settingsModal").classList.add("open");
    loadTaskStatus();
    loadMissingReport();
    loadBackupStatus();
    loadCategoriesForRename();
}
function closeSettings() { document.getElementById("settingsModal").classList.remove("open"); }

/* ── RENOMMAGE DES CATÉGORIES EN MASSE ────────────────── */
async function loadCategoriesForRename() {
    const select = document.getElementById("catRenameSelect");
    select.innerHTML = '<option value="">Chargement...</option>';
    try {
        const r = await fetch(API_BASE + "/api/categories");
        const data = await r.json();
        let html = '<option value="">-- Choisir une catégorie --</option>';
        const sortedCats = Object.keys(data).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
        for (const cat of sortedCats) {
            if (cat !== ".None") {
                html += `<option value="${escapeHtml(cat)}|">${escapeHtml(cat)} (Catégorie entière)</option>`;
                for (const subcat of data[cat]) {
                    html += `<option value="${escapeHtml(cat)}|${escapeHtml(subcat)}">${escapeHtml(cat)} &gt; ${escapeHtml(subcat)}</option>`;
                }
            }
        }
        select.innerHTML = html;
    } catch (e) {}
}

function onRenameSelectChange() {
    const val = document.getElementById('catRenameSelect').value;
    if(!val) {
        document.getElementById('catRenameInputCat').value = "";
        document.getElementById('catRenameInputSubcat').value = "";
        return;
    }
    const parts = val.split('|');
    document.getElementById('catRenameInputCat').value = parts[0];
    document.getElementById('catRenameInputSubcat').value = parts[1] || "";
}

async function renameCategoryAction() {
    const select = document.getElementById("catRenameSelect");
    const inputCat = document.getElementById("catRenameInputCat");
    const inputSub = document.getElementById("catRenameInputSubcat");
    const status = document.getElementById("catRenameStatus");
    const btn = document.getElementById("catRenameBtn");

    if (!select.value) return;
    const oldParts = select.value.split('|');
    const oldCat = oldParts[0];
    const oldSub = oldParts[1];
    
    const newCat = inputCat.value.trim();
    const newSub = inputSub.value.trim();

    if (!newCat) {
        status.textContent = "Le nom de la catégorie est obligatoire.";
        status.style.display = "inline";
        return;
    }

    btn.disabled = true;
    status.textContent = "Mise à jour...";
    status.style.color = "#888";
    status.style.display = "inline";

    try {
        const r = await fetch(API_BASE + "/api/categories/rename", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({
                token: API_TOKEN, 
                old_category: oldCat, old_subcategory: oldSub,
                new_category: newCat, new_subcategory: newSub
            })
        });
        if (r.ok) {
            status.textContent = "Succès !";
            status.style.color = "#27ae60";
            loadCategoriesForRename(); 
            loadCategories(); 
            document.querySelectorAll(".thumbnail").forEach(div => {
                if (div.dataset.category === oldCat && (!oldSub || div.dataset.subcategory === oldSub)) {
                    div.dataset.category = newCat;
                    div.dataset.subcategory = newSub || "none";
                    div.dataset.search = (div.dataset.basename + " " + newCat + " " + newSub).toLowerCase();
                }
            });
        }
    } catch(e) { status.textContent = "Erreur."; }
    btn.disabled = false;
}

async function loadTaskStatus() {
    const toggle     = document.getElementById("scheduleToggle");
    const hInput     = document.getElementById("intervalHours");
    const mInput     = document.getElementById("intervalMinutes");
    const taskStatus = document.getElementById("taskStatus");
    taskStatus.textContent = "Chargement...";
    taskStatus.style.color = "#aaa";
    toggle.disabled = true;
    try {
        const r    = await fetch(API_BASE + "/schedule/status");
        const data = await r.json();
        toggle.checked  = data.enabled;
        toggle.disabled = false;
        const total = data.interval_minutes || 90;
        hInput.value = String(Math.floor(total / 60)).padStart(2, "0");
        mInput.value = String(total % 60).padStart(2, "0");
        updateTaskStatus(data.enabled);
    } catch(e) {
        taskStatus.textContent = "Impossible de joindre RENDER-01";
        taskStatus.style.color = "#e74c3c";
    }
}

function updateTaskStatus(enabled) {
    const taskStatus = document.getElementById("taskStatus");
    const hInput     = document.getElementById("intervalHours");
    const mInput     = document.getElementById("intervalMinutes");
    if (enabled) {
        const h = parseInt(hInput.value) || 0;
        const m = parseInt(mInput.value) || 0;
        const label = (h > 0 ? h + "h" : "") + (m > 0 ? m + "min" : "");
        taskStatus.textContent = "Activée — toutes les " + (label || "90min");
        taskStatus.style.color = "#27ae60";
    } else {
        taskStatus.textContent = "Désactivée";
        taskStatus.style.color = "#aaa";
    }
}

async function toggleTask() {
    const toggle = document.getElementById("scheduleToggle");
    toggle.disabled  = true;
    await saveScheduleConfig();
    toggle.disabled = false;
}

async function setTaskInterval() { await saveScheduleConfig(); }

async function saveScheduleConfig() {
    const toggle = document.getElementById("scheduleToggle");
    const hInput = document.getElementById("intervalHours");
    const mInput = document.getElementById("intervalMinutes");
    const taskStatus = document.getElementById("taskStatus");
    const h = Math.min(99, Math.max(0, parseInt(hInput.value) || 0));
    const m = Math.min(59, Math.max(0, parseInt(mInput.value) || 0));
    const total = h * 60 + m;
    if (total < 1) {
        taskStatus.textContent = "Intervalle minimum : 1 minute";
        taskStatus.style.color = "#e74c3c";
        return;
    }
    try {
        const r = await fetch(API_BASE + "/schedule/update", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({token: API_TOKEN, enabled: toggle.checked, interval_minutes: total})
        });
        const data = await r.json();
        updateTaskStatus(data.enabled);
    } catch(e) {
        taskStatus.textContent = "Erreur";
        taskStatus.style.color = "#e74c3c";
        toggle.checked = !toggle.checked;
    }
}

/* ── REPORT DES FICHIERS MANQUANTS ───────────────────── */
async function loadMissingReport() {
    const container = document.getElementById("missingReport");
    container.innerHTML = '<span style="color:#aaa;font-size:12px;">Chargement...</span>';
    try {
        const r    = await fetch(API_BASE + "/library/info");
        const data = await r.json();
        if (data.status === "not_found") {
            container.innerHTML = '<span style="color:#aaa;font-size:12px;">Aucune donnée — régénérez la bibliothèque.</span>';
            return;
        }
        const genDate = data.generated || "inconnue";
        const missing = data.missing   || [];
        if (missing.length === 0) {
            container.innerHTML =
                '<span style="font-size:12px;color:#27ae60;">&#10003; Aucun fichier manquant</span>' +
                '<span style="font-size:11px;color:#bbb;margin-left:10px;">Généré le ' + genDate + '</span>';
        } else {
            let html = '<div style="font-size:12px;color:#e74c3c;margin-bottom:6px;">' + missing.length + ' fichier(s) manquant(s) — Généré le ' + genDate + '</div>';
            html += '<div style="max-height:120px;overflow-y:auto;font-size:11px;">';
            missing.forEach(m => {
                const icon  = m.missing === "max" ? "📄" : "🖼";
                const label = m.missing === "max" ? "fichier .max manquant" : "image manquante";
                const winPath = (m.path || "")
                    .replace(/^\/\/CGLibrary\/CgLibrary\/3-Models/, "L:\\3-Models")
                    .replace(/^\\\\CGLibrary\\CgLibrary\\3-Models/, "L:\\3-Models")
                    .replace(/\//g, "\\");
                const linkHtml = winPath
                    ? ' <a href="#" onclick="event.preventDefault();navigator.clipboard.writeText(\'' + winPath.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + '\').then(()=>showNotification(\'&#10003; Chemin copié !\'))" style="font-size:11px;color:#0066cc;text-decoration:none;" title="' + winPath + '">[ouvrir]</a>'
                    : "";
                html += '<div style="padding:2px 0;color:#888;">' + icon + ' <b>' + m.name + '</b> — ' + label + linkHtml + '</div>';
            });
            html += '</div>';
            container.innerHTML = html;
        }
    } catch(e) { container.innerHTML = '<span style="color:#e74c3c;font-size:12px;">Impossible de joindre RENDER-01</span>'; }
}

/* ── REGENERATE ───────────────────────────────────────── */
async function regenerateLibrary(htmlOnly = false) {
    const btn1 = document.getElementById("regenBtn");
    const btn2 = document.getElementById("regenPageBtn");
    const status = document.getElementById("regenStatus");
    btn1.disabled = true;
    btn2.disabled = true;
    status.style.display = "none";
    
    const args = htmlOnly ? "--html-only" : "";
    
    try {
        const resp = await fetch(API_BASE + "/run/Models_checked_update.py", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({token: API_TOKEN, args: args})
        });
        const data = await resp.json();
        if (data.status === "Success") {
            status.textContent   = htmlOnly ? "Régénération HTML..." : "Scan en cours...";
            status.style.color   = "#888";
            status.style.display = "inline";
            pollRegenStatus(data.job_id, btn1, btn2, status);
        } else {
            status.textContent = "Erreur : " + data.message;
            status.style.color = "#e74c3c";
            status.style.display = "inline";
            btn1.disabled = false; btn2.disabled = false;
        }
    } catch(e) {
        status.textContent = "Erreur serveur";
        status.style.color = "#e74c3c";
        status.style.display = "inline";
        btn1.disabled = false; btn2.disabled = false;
    }
}

function pollRegenStatus(jobId, btn1, btn2, status) {
    const iv = setInterval(async () => {
        try {
            const r = await fetch(API_BASE + "/job-status/" + jobId);
            const data = await r.json();
            if (data.status === "done") {
                clearInterval(iv);
                status.innerHTML = "&#10003; Terminé — rechargement...";
                status.style.color = "#27ae60";
                setTimeout(() => window.location.reload(), 1500);
            } else if (data.status === "error") {
                clearInterval(iv);
                status.textContent = "Erreur d'exécution";
                status.style.color = "#e74c3c";
                btn1.disabled = false; btn2.disabled = false;
            }
        } catch(e) {}
    }, 2000);
}

function pollRegenStatus(jobId, btn, status) {
    const iv = setInterval(async () => {
        try {
            const r    = await fetch(API_BASE + "/job-status/" + jobId);
            const data = await r.json();
            if (data.status === "done") {
                clearInterval(iv);
                status.innerHTML   = "&#10003; Régénérée — rechargement dans 3s...";
                status.style.color = "#27ae60";
                btn.disabled    = false;
                btn.textContent = "Régénérer maintenant";
                setTimeout(() => {
                    closeSettings();
                    window.location.reload();
                }, 3000);
            } else if (data.status === "error") {
                clearInterval(iv);
                status.textContent = "Erreur lors de la génération";
                status.style.color = "#e74c3c";
                btn.disabled    = false;
                btn.textContent = "Régénérer maintenant";
            }
        } catch(e) {}
    }, 4000);
}

/* ── BACKUP ───────────────────────────────────────────── */
async function loadBackupStatus() {
    const info = document.getElementById("backupInfo");
    try {
        const r    = await fetch(API_BASE + "/backup/status");
        const data = await r.json();
        info.textContent = data.last_backup ? "Dernier backup : " + data.last_backup : "Aucun backup effectué";
        info.style.color = "#999";
    } catch(e) {
        info.textContent = "Impossible de joindre RENDER-01";
        info.style.color = "#e74c3c";
    }
}

async function startBackup() {
    const btn    = document.getElementById("backupBtn");
    const status = document.getElementById("backupStatus");
    btn.disabled    = true;
    btn.textContent = "En cours...";
    status.style.display = "none";
    try {
        const resp = await fetch(API_BASE + "/backup/start", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({token: API_TOKEN})
        });
        const data = await resp.json();
        if (data.status === "Success") {
            status.textContent   = "Backup en cours...";
            status.style.color   = "#888";
            status.style.display = "inline";
            pollBackupStatus(data.job_id, btn, status);
        } else {
            status.textContent   = "Erreur : " + (data.detail || "inconnue");
            status.style.color   = "#e74c3c";
            status.style.display = "inline";
            btn.disabled    = false;
            btn.textContent = "Lancer le backup";
        }
    } catch(e) {
        status.textContent   = "Impossible de joindre RENDER-01";
        status.style.color   = "#e74c3c";
        status.style.display = "inline";
        btn.disabled    = false;
        btn.textContent = "Lancer le backup";
    }
}

function pollBackupStatus(jobId, btn, status) {
    const iv = setInterval(async () => {
        try {
            const r    = await fetch(API_BASE + "/job-status/" + jobId);
            const data = await r.json();
            if (data.status === "done") {
                clearInterval(iv);
                status.innerHTML   = "&#10003; Backup terminé !";
                status.style.color = "#27ae60";
                btn.disabled    = false;
                btn.textContent = "Lancer le backup";
                loadBackupStatus();
            } else if (data.status === "error") {
                clearInterval(iv);
                status.textContent = "Erreur — vérifiez que le poste Antoine est allumé";
                status.style.color = "#e74c3c";
                btn.disabled    = false;
                btn.textContent = "Lancer le backup";
            }
        } catch(e) {}
    }, 5000);
}

function openAbout() { document.getElementById("aboutModal").classList.add("open"); }
function closeAbout() { document.getElementById("aboutModal").classList.remove("open"); }

/* ── ÉDITEUR DE KEYWORDS ─────────────────────────────── */
let currentTxtPath = null;

function openKwEditorFromBtn() {
    const div = document.querySelector(".thumbnail.last-clicked");
    if (div) openKwEditor(div);
    else alert("Cliquez d'abord sur un asset pour le sélectionner.");
}

function openKwEditor(div) {
    currentTxtPath = div.dataset.txtPath;
    document.getElementById("kwBasename").textContent     = div.dataset.basename;
    document.getElementById("kwPath").textContent         = div.dataset.txtPath;
    document.getElementById("kwCategory").value           = "";
    document.getElementById("kwSubcategory").value        = "";
    
    // On vide le conteneur et on affiche "Chargement..."
    document.getElementById("kwInputsContainer").innerHTML = "<div style='font-size:12px;color:#888;'>Chargement...</div>";
    document.getElementById("kwSaveStatus").style.display = "none";
    document.getElementById("kwModal").classList.add("open");

    fetch(API_BASE + "/read-txt", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({token: API_TOKEN, path: currentTxtPath})
    })
    .then(r => r.json())
    .then(data => {
        if (data.content !== undefined) parseTxtIntoForm(data.content);
        else document.getElementById("kwInputsContainer").innerHTML = "<div style='color:#e74c3c;'>Erreur de lecture</div>";
    })
    .catch(() => document.getElementById("kwInputsContainer").innerHTML = "<div style='color:#e74c3c;'>Serveur injoignable</div>");
}

function parseTxtIntoForm(content) {
    const lines = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
    let cat = "", subcat = "", kws = [];
    for (let line of lines) {
        line = line.trim();
        if (!line) continue;
        if (line.startsWith("--"))     subcat = line.slice(2).trim();
        else if (line.startsWith("-")) cat    = line.slice(1).trim();
        else                           kws.push(line);
    }
    document.getElementById("kwCategory").value    = cat;
    document.getElementById("kwSubcategory").value = subcat;
    
    // Générer les champs de mots-clés dynamiques
    const container = document.getElementById("kwInputsContainer");
    container.innerHTML = "";
    if (kws.length === 0) addKwInputRow(""); // Au moins un champ vide
    else kws.forEach(kw => addKwInputRow(kw));
}

async function saveKwEditor() {
    const cat      = document.getElementById("kwCategory").value.trim();
    const subcat   = document.getElementById("kwSubcategory").value.trim();
    const btn      = document.getElementById("kwSaveBtn");
    const status   = document.getElementById("kwSaveStatus");
    const basename = document.getElementById("kwBasename").textContent;

    // Récupérer toutes les valeurs des petits champs dynamiques
    const inputs = document.querySelectorAll(".single-kw");
    const kwList = Array.from(inputs).map(inp => inp.value.trim()).filter(v => v !== "");

    // Reconstruction du fichier texte
    const lines = [];
    if (cat)    lines.push("-"  + cat);
    if (subcat) lines.push("--" + subcat);
    if (kwList.length > 0) lines.push(...kwList);
    const content = lines.join("\n") + "\n";

    btn.disabled         = true;
    status.style.display = "none";
    
    try {
        // 1. Sauvegarde sur le réseau
        const resp = await fetch(API_BASE + "/write-txt", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({token: API_TOKEN, path: currentTxtPath, content: content})
        });
        const data = await resp.json();
        if (data.status !== "ok") {
            status.textContent = "Erreur réseau : " + data.detail;
            status.style.color = "#e74c3c";
            status.style.display = "block";
            btn.disabled = false;
            return;
        }
        
        // 2. Mise à jour de la BDD SQLite
        const updateResp = await fetch(API_BASE + "/library/update-asset", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({ token: API_TOKEN, name: basename, category: cat, subcategory: subcat, keywords: kwList })
        });
        await updateResp.json();

        // 3. Mise à jour de l'interface en direct
        const div = document.querySelector(".thumbnail.last-clicked");
        if (div) {
            const newSearch = (basename + " " + cat + " " + subcat + " " + kwList.join(" ")).toLowerCase();
            div.dataset.search      = newSearch;
            div.dataset.category    = cat   || ".None";
            div.dataset.subcategory = subcat || "none";
        }
        
        status.textContent   = "Enregistré !";
        status.style.color   = "#27ae60";
        status.style.display = "block";
        
        loadCategories();
        loadAllKeywords(); // Met à jour la liste d'auto-complétion
        setTimeout(() => closeKwModal(), 1000);
        
    } catch(e) {
        status.textContent = "Impossible de joindre le serveur";
        status.style.color = "#e74c3c";
        status.style.display = "block";
    }
    btn.disabled = false;
}

function closeKwModal() {
    document.getElementById("kwModal").classList.remove("open");
    currentTxtPath = null;
}
"""

CSS = """
body { font-family: "Fira Sans", sans-serif; margin: 0; display: flex; background-color: #fcfcfc; }
#sidebar { position: fixed; z-index: 10; width: 250px; background-color: #f4f4f4; padding-left: 12px; padding-top: 12px; padding-bottom: 40px; height: 100vh; overflow-y: auto; border-right: 2px solid #ccc; box-sizing: border-box; }
.sidebar-category { font-weight: 400; font-size: 14px; margin: 5px 0; margin-top: 8px; cursor: pointer; display: flex; align-items: center; gap: 4px; }
.sidebar-subcategory { font-weight: 300; font-size: 13px; margin-left: 19px; margin-bottom: 5px; color: #555; cursor: pointer; }
.sidebar-category.active, .sidebar-subcategory.active { color: #0066cc; font-weight: 500; }
.subcategory-container { display: block; }
.arrow { font-size: 9px; color: #aaa; cursor: pointer; user-select: none; flex-shrink: 0; width: 12px; text-align: center; }
#main { flex: 1; padding: 0; margin-left: 250px; }
#infoBar { background-color: #fcfcfc; position: fixed; width: 100%; z-index: 5; }
#navBar { display: flex; align-items: center; gap: 12px; padding-top: 20px; margin-left: 50px; margin-bottom: 4px; }
#navTitle { font-weight: 700; font-size: 14px; letter-spacing: 0.08em; }
#navSep { color: #ccc; }
.nav-link { font-weight: 300; font-size: 14px; letter-spacing: 0.08em; color: #888; cursor: pointer; }
.nav-link:hover { color: #333; }
.conn-dot-wrap { display: flex; align-items: center; gap: 6px; }
#navConnDot { width: 8px; height: 8px; border-radius: 50%; background: #e74c3c; flex-shrink: 0; }
#navConnTip { font-size: 11px; color: #e74c3c; font-weight: 500; }
.copy-notification { position: fixed; bottom: 30px; right: 30px; background: #27ae60; color: white; padding: 15px 25px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.2); opacity: 0; transform: translateY(20px); transition: all 0.3s; pointer-events: auto; font-weight: 600; z-index: 1000; }
.copy-notification.show { opacity: 1; transform: translateY(0); }
.modal-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.35); z-index: 200; align-items: center; justify-content: center; }
.modal-overlay.open { display: flex; }
.modal-box { background: #fff; border-radius: 10px; padding: 30px 36px; min-width: 380px; max-width: 560px; width: 100%; box-shadow: 0 12px 40px rgba(0,0,0,0.18); position: relative; max-height: 90vh; overflow-y: auto; }
.modal-box h2 { font-size: 15px; font-weight: 600; letter-spacing: 0.08em; margin: 0 0 22px; }
.modal-close { position: absolute; top: 16px; right: 20px; background: none; border: none; font-size: 20px; cursor: pointer; color: #aaa; line-height: 1; }
.modal-close:hover { color: #333; }
.modal-section { margin-bottom: 22px; padding-bottom: 22px; border-bottom: 1px solid #eee; }
.modal-section:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
.modal-section > label { font-size: 13px; font-weight: 500; display: block; margin-bottom: 10px; }
.modal-section p.hint { font-size: 12px; color: #999; margin: 6px 0 0; }
.btn-primary { font-family: "Fira Sans", sans-serif; background: #222; color: #fff; border: none; padding: 9px 20px; border-radius: 6px; font-size: 13px; cursor: pointer; transition: background 0.2s; }
.btn-primary:hover { background: #444; }
.btn-primary:disabled { background: #aaa; cursor: default; }
#regenStatus, #backupStatus { font-size: 12px; margin-left: 12px; display: none; }
.schedule-row { display: flex; align-items: center; gap: 12px; margin-top: 4px; }
.interval-input { font-family: "Fira Sans", sans-serif; font-size: 13px; padding: 6px 10px; border: 1px solid #ddd; border-radius: 6px; width: 52px; text-align: center; }
.toggle-switch { position: relative; width: 40px; height: 22px; flex-shrink: 0; }
.toggle-switch input { opacity: 0; width: 0; height: 0; }
.toggle-slider { position: absolute; inset: 0; background: #ccc; border-radius: 22px; cursor: pointer; transition: background 0.2s; }
.toggle-slider:before { content: ""; position: absolute; width: 16px; height: 16px; left: 3px; top: 3px; background: white; border-radius: 50%; transition: transform 0.2s; }
.toggle-switch input:checked + .toggle-slider { background: #222; }
.toggle-switch input:checked + .toggle-slider:before { transform: translateX(18px); }
#kwModal .modal-box { min-width: 420px; }
#kwBasename { font-weight: 600; font-size: 14px; margin-bottom: 4px; }
#kwPath { font-size: 11px; color: #aaa; margin-bottom: 16px; word-break: break-all; }
.kw-field { width: 100%; box-sizing: border-box; font-family: "Fira Sans", sans-serif; font-size: 13px; padding: 7px 10px; border: 1px solid #ddd; border-radius: 6px; margin-bottom: 10px; }
#kwKeywords { height: 100px; resize: vertical; }
.kw-hint { font-size: 11px; color: #bbb; margin: -6px 0 14px; }
#kwSaveStatus { font-size: 12px; margin-left: 12px; display: none; }
#backupInfo { font-size: 12px; color: #999; margin-top: 8px; }
.about-version { font-size: 22px; font-weight: 700; letter-spacing: 0.05em; margin-bottom: 6px; }
.about-desc { font-size: 13px; color: #555; line-height: 1.7; margin-bottom: 20px; }
.about-soon { font-size: 12px; color: #aaa; line-height: 1.8; }
.about-meta { font-size: 11px; color: #bbb; border-top: 1px solid #eee; padding-top: 14px; margin-top: 4px; }

/* --- NOUVELLES REGLES CSS POUR LES UTILISATEURS ET FAVORIS --- */
.thumbnail { position: relative; display: inline-block; margin: 10px; text-align: center; width: 220px; }
.heart-icon { position: absolute; top: 8px; right: 8px; font-size: 24px; color: rgba(255, 255, 255, 0.3); display: none; pointer-events: none; text-shadow: 0 0 4px rgba(0,0,0,0.6); z-index: 2; }
.thumbnail.is-favorite .heart-icon { display: block; color: rgba(253, 253, 253, 0.9); }
.kw-field-row { display: flex; gap: 8px; margin-bottom: 10px; }
.user-item { display: flex; align-items: center; justify-content: space-between; padding: 6px 8px; border-bottom: 1px solid #eee; font-size: 13px; }
.user-item span { cursor: pointer; flex-grow: 1; }
.user-item .user-actions { display: flex; gap: 6px; }
.user-action-btn { background: none; border: none; cursor: pointer; font-size: 12px; color: #888; }
.user-action-btn:hover { color: #333; }
/* Effets de survol et de sélection pour les miniatures */
.thumbnail { transition: all 0.2s ease-in-out; border-radius: 3px; }
.thumbnail:hover { box-shadow: 0 6px 12px rgba(0,0,0,0.08); z-index: 3; }
.thumbnail.last-clicked { 
    box-shadow: 0 0 0 3px rgba(0,0,0,0.05), 0 0 0 8px rgba(0,0,0,0.01); 
    transform: scale(1.03); 
    z-index: 5; 
    background-color: #DBE0E5;
}
.thumbnail.last-clicked img { border-radius: 4px; }
.thumbnail img { object-fit: cover; border-radius: 4px; }
.proxy-icon { position: absolute; bottom: 8px; right: 8px; font-size: 11px; font-weight: 700; color: #ffffff; background: rgba(0,0,0,0.65); padding: 4px 7px; border-radius: 4px; cursor: pointer; z-index: 4; transition: all 0.2s; pointer-events: auto; backdrop-filter: blur(2px); letter-spacing: 0.05em; }
.proxy-icon:hover { color: #e67e22; background: rgba(0,0,0,0.85); }
.proxy-icon.active { color: #ffffff; background: #e67e22; box-shadow: 0 0 8px rgba(230, 126, 34, 0.6); }
/* Auto-complétion */
.autocomplete-wrapper { position: relative; width: 100%; }
.autocomplete-items { position: absolute; border: 1px solid #ddd; border-top: none; z-index: 99; top: 100%; left: 0; right: 0; max-height: 150px; overflow-y: auto; background-color: #fff; border-radius: 0 0 6px 6px; box-shadow: 0 6px 12px rgba(0,0,0,0.1); display: none; }
.autocomplete-items div { padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #f4f4f4; font-size: 13px; color: #333; }
.autocomplete-items div:hover { background-color: #f0f7ff; color: #0066cc; }
"""

# ── LECTURE INSTRUCTIONS.TXT ──────────────────────────────────────────────────
instructions_path = r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\instructions.txt"
about_desc_html = '<div class="about-desc">Fichier d\'instructions introuvable.</div>'
about_soon_html = ''

try:
    if os.path.exists(instructions_path):
        with open(instructions_path, "r", encoding="utf-8-sig") as f:
            content = f.read()
        
        # On découpe le fichier au niveau des tirets "---"
        if "---" in content:
            desc_part, soon_part = content.split("---", 1)
            # On remplace les retours à la ligne par des <br> pour l'HTML
            about_desc_html = f'<div class="about-desc">{desc_part.strip().replace(chr(10), "<br>")}</div>'
            about_soon_html = f'<div class="about-soon">{soon_part.strip().replace(chr(10), "<br>")}</div>'
        else:
            about_desc_html = f'<div class="about-desc">{content.strip().replace(chr(10), "<br>")}</div>'
except Exception as e:
    print(f"<!> Erreur lors de la lecture de instructions.txt : {e}")


parts = [
'<!DOCTYPE html><html><head><meta charset="utf-8"><title>MODELS</title>',
'<link href="https://fonts.googleapis.com/css2?family=Fira+Sans:wght@200;300;400;500;700&display=swap" rel="stylesheet">',
'<style>', CSS, '</style>',
'<script>', JS, '</script>',
'</head><body>',
'<div id="sidebar"></div>',
'<div id="main"><div id="infoBar">',
'<div id="navBar">',
'<span id="navTitle">3D MODELS</span>',
'<span id="navSep">|</span>',
'<span class="nav-link" onclick="openSettings()">SETTINGS</span>',
'<span id="navSep">|</span>',
'<span class="nav-link" onclick="openAbout()">ABOUT</span>',
'<span id="navSep">|</span>',
'<span class="nav-link" id="navUserBtn" onclick="openUserModal()">USER</span>',
'<span id="navFavSep" style="display:none; color:#ccc;">|</span>',
'<span class="nav-link" id="navFavModeBtn" onclick="toggleFavMode()" style="display:none;">FAVORIS MODE</span>',
'<div class="conn-dot-wrap" style="margin-left:8px;">',
'<div id="navConnDot" style="display:none;width:8px;height:8px;border-radius:50%;background:#e74c3c;"></div>',
'<span id="navConnTip" style="display:none;font-size:11px;color:#e74c3c;font-weight:500;margin-left:4px;"></span>',
'</div>',
'</div>',

# ── BARRE DE RECHERCHE ET BOUTONS (Version propre et corrigée) ──
'<div style="display:flex;align-items:center;margin-left:50px;margin-bottom:12px;">',
'<input type="text" id="searchInput" placeholder="Rechercher..."',
' style="width:400px;padding:8px;font-size:15px;font-family:\'Fira Sans\',sans-serif;height:34px;box-sizing:border-box;"',
' oninput="setSearch(this.value)">',
'<button onclick="clearSearch()" style="height:34px;padding:0 10px;font-size:15px;margin-left:6px;cursor:pointer;">&#x2715;</button>',
'<button onclick="openAdvSearch()" style="height:34px;padding:0 12px;font-size:13px;margin-left:6px;font-family:\'Fira Sans\',sans-serif;cursor:pointer;background:#eee;border:1px solid #ccc;border-radius:4px;">&#x2699; Filtres</button>',
'<button onclick="openKwEditorFromBtn()" style="height:34px;padding:0 12px;font-size:13px;margin-left:6px;font-family:\'Fira Sans\',sans-serif;cursor:pointer;">&#x270E; Keywords</button>',
'<button onclick="toggleFavoriteFromBtn()" style="height:34px;padding:0 12px;font-size:13px;margin-left:6px;font-family:\'Fira Sans\',sans-serif;cursor:pointer;color:#222;">&#x2764; Favoris</button>',
'<div id="thumbnailInfo" style="display:inline-block;margin-left:16px;padding:8px 12px;background-color:#fcfcfc;border-radius:6px;font-size:13px;color:#333;min-width:300px;"></div>',
'</div></div>',
# ────────────────────────────────────────────────────────────────

'<div id="thumbnailsContainer" style="margin-left:50px;margin-top:110px;">',
thumbnails_html,
'</div></div>',

# Settings modal
'<div class="modal-overlay" id="settingsModal" onclick="if(event.target===this)closeSettings()">',
'<div class="modal-box">',
'<button class="modal-close" onclick="closeSettings()">&#x2715;</button>',
'<h2>SETTINGS</h2>',

# 1. Régénérer (Avec les DEUX boutons)
'<div class="modal-section">',
'<label>Génération de la bibliothèque</label>',
'<div style="display:flex; gap:10px; margin-bottom:6px;">',
'<button class="btn-primary" id="regenBtn" onclick="regenerateLibrary(false)">Régénérer (Scan Complet)</button>',
'<button class="btn-primary" id="regenPageBtn" onclick="regenerateLibrary(true)" style="background:#555;">Régénérer HTML (Rapide)</button>',
'</div>',
'<span id="regenStatus" style="font-size: 12px; display: none;"></span>',
'<p class="hint">Le scan complet cherche les nouveaux fichiers. Le mode rapide reconstruit juste la page visuelle.</p>',
'</div>',

# 2. Schedule
'<div class="modal-section">',
'<label>Régénération automatique</label>',
'<div class="schedule-row">',
'<label class="toggle-switch"><input type="checkbox" id="scheduleToggle" onchange="toggleTask()"><span class="toggle-slider"></span></label>',
'<span id="taskStatus" style="font-size:13px;color:#aaa;">Chargement...</span>',
'</div>',
'<div class="schedule-row" style="margin-top:12px;">',
'<span style="font-size:13px;color:#555;">Toutes les</span>',
'<input type="number" class="interval-input" id="intervalHours" min="0" max="99" value="01" onchange="setTaskInterval()">',
'<span style="font-size:13px;color:#555;">h</span>',
'<input type="number" class="interval-input" id="intervalMinutes" min="0" max="59" value="30" onchange="setTaskInterval()">',
'<span style="font-size:13px;color:#555;">min</span>',
'</div>',
'<p class="hint">Contrôlé via scheduler.py sur RENDER-01. Fonctionne même si la page est fermée.</p>',
'</div>',

# 3. Missing Report
'<div class="modal-section">',
'<label>Rapport des fichiers manquants</label>',
'<div id="missingReport"><span style="color:#aaa;font-size:12px;">Chargement...</span></div>',
'</div>',

# 4. Backup
'<div class="modal-section">',
f'<label>Backup vers \\\\Antoine\\3-Models</label>',
'<button class="btn-primary" id="backupBtn" onclick="startBackup()">Lancer le backup</button>',
'<span id="backupStatus"></span>',
'<div id="backupInfo">Chargement...</div>',
'<p class="hint">Miroir complet vers le poste Antoine. Le poste doit être allumé et connecté au réseau.</p>',
'</div>',

# 5. L'Outil de renommage (Avec gestion des sous-catégories)
'<div class="modal-section">',
'<label>Renommer une Catégorie / Sous-catégorie</label>',
'<select class="kw-field" id="catRenameSelect" style="margin-bottom: 8px; cursor: pointer;" onchange="onRenameSelectChange()"></select>',
'<div style="display: flex; gap: 8px; margin-bottom: 6px;">',
'<input type="text" class="kw-field" id="catRenameInputCat" placeholder="Catégorie Principale" style="margin-bottom: 0;">',
'<input type="text" class="kw-field" id="catRenameInputSubcat" placeholder="Sous-catégorie (optionnel)" style="margin-bottom: 0;">',
'</div>',
'<button class="btn-primary" id="catRenameBtn" onclick="renameCategoryAction()">Renommer</button>',
'<span id="catRenameStatus" style="font-size: 12px; margin-left: 12px; display: none;"></span>',
'<p class="hint">Modifie la base de données ET réécrit les fichiers _CHECKED_OK.txt correspondants.</p>',
'</div>',

# 6. Statut de connexion
'<div class="modal-section">',
'<div class="conn-dot-wrap">',
'<div id="connDot" style="width:8px;height:8px;border-radius:50%;background:#ccc;flex-shrink:0;"></div>',
'<span id="connTip" style="font-size:12px;color:#aaa;margin-left:6px;">Chargement...</span>',
'</div>',
'</div>',
'</div></div>',

# About modal
'<div class="modal-overlay" id="aboutModal" onclick="if(event.target===this)closeAbout()">',
'<div class="modal-box">',
'<button class="modal-close" onclick="closeAbout()">&#x2715;</button>',
'<h2>ABOUT</h2>',
'<div class="about-version">3D Models Library</div>',
f'<div style="font-size:11px;color:#bbb;margin-bottom:16px;">Version {VERSION}</div>',
about_desc_html,
about_soon_html,
'<div class="about-meta">',
f'<div>Généré le : {generated_at}</div>',
f'<div>Assets référencés : {found}</div>',
'<div>Serveur : RENDER-01 (10.13.54.151:8000)</div>',
'</div>',
'</div></div>',

# Keyword editor modal
'<div class="modal-overlay" id="kwModal">',
'<div class="modal-box" style="width: 450px;">',
'<button class="modal-close" onclick="closeKwModal()">&#x2715;</button>',
'<h2>ÉDITER LES KEYWORDS</h2>',
'<div id="kwBasename" style="font-weight:600; font-size:14px; margin-bottom:4px;"></div>',
'<div id="kwPath" style="font-size:11px; color:#aaa; margin-bottom:16px; word-break:break-all;"></div>',

'<div style="display:flex; gap:10px;">',
'<div style="flex:1;"><label style="font-size:12px;font-weight:500;">Catégorie</label><input type="text" class="kw-field" id="kwCategory"></div>',
'<div style="flex:1;"><label style="font-size:12px;font-weight:500;">Sous-catégorie</label><input type="text" class="kw-field" id="kwSubcategory"></div>',
'</div>',

'<label style="font-size:12px;font-weight:500; margin-top:10px; display:block;">Mots-clés (Auto-complétion activée)</label>',
# La datalist native HTML qui contiendra tous les mots de la BDD
'<datalist id="allKeywordsList"></datalist>', 
# Le conteneur qui recevra les petits champs textes dynamiques
'<div id="kwInputsContainer" style="max-height:200px; overflow-y:auto; margin-bottom:10px; padding-right:5px;"></div>',
'<button class="btn-primary" onclick="addKwInputRow(\'\')" style="background:#555; width:100%; margin-bottom:15px;">+ Ajouter un mot-clé</button>',

'<button class="btn-primary" id="kwSaveBtn" onclick="saveKwEditor()" style="width:100%;">Enregistrer les modifications</button>',
'<span id="kwSaveStatus" style="display:none; text-align:center; margin-top:10px; display:block; font-size:13px;"></span>',
'</div></div>',

# ── NEW USER MODAL ────────────────────────────────────────────────────────────
'<div class="modal-overlay" id="userModal" onclick="if(event.target===this)closeUserModal()">',
'<div class="modal-box">',
'<button class="modal-close" onclick="closeUserModal()">&#x2715;</button>',
'<h2>GESTION UTILISATEURS</h2>',
'<div class="modal-section">',
'<label>Créer un utilisateur</label>',
'<div class="kw-field-row">',
'<input type="text" class="kw-field" id="newUsernameInput" placeholder="Nom de l\'utilisateur" style="margin-bottom:0;">',
'<button class="btn-primary" onclick="createUserAction()">Créer</button>',
'</div>',
'</div>',
'<div class="modal-section">',
'<label>Sélectionner un utilisateur actif</label>',
'<div id="userListContainer"></div>',
'</div>',
'</div></div>',

'<div class="copy-notification" id="copyNotification"></div>',

# ── ADVANCED SEARCH MODAL ─────────────────────────────────────────────────────
'<div class="modal-overlay" id="advSearchModal" onclick="if(event.target===this)closeAdvSearch()">',
'<div class="modal-box" style="min-width: 400px;">',
'<button class="modal-close" onclick="closeAdvSearch()">&#x2715;</button>',
'<h2>FILTRES AVANCÉS</h2>',

'<div class="modal-section">',
'<label>Trier les modèles par :</label>',
'<select class="kw-field" id="advSortSelect">',
'<option value="date_desc">Ajout récent en premier</option>',
'<option value="date_asc">Plus anciens en premier</option>',
'<option value="az">Nom (A vers Z)</option>',
'<option value="za">Nom (Z vers A)</option>',
'</select>',
'</div>',

'<div class="modal-section">',
'<label>Exclure Catégorie / Sous-catégorie :</label>',
'<select class="kw-field" id="advExcludeSelect"></select>',
'<label style="margin-top:10px;">Exclure ces mots (séparés par virgule) :</label>',
'<input type="text" class="kw-field" id="advExcludeWords" placeholder="ex: wood, metal, table">',
'</div>',

'<div class="modal-section">',
'<label style="display:flex; align-items:center; cursor:pointer; margin-bottom:8px;">',
'<input type="checkbox" id="advFavFirstCheck" style="margin-right:8px; transform:scale(1.2);"> ',
'Afficher les FAVORIS en premier',
'</label>',
'<label style="display:flex; align-items:center; cursor:pointer;">',
'<input type="checkbox" id="advProxyCheck" style="margin-right:8px; transform:scale(1.2);"> ',
'Afficher UNIQUEMENT les modèles avec Proxy',
'</label>',
'</div>',

'<div style="display:flex; gap:10px; margin-top:10px;">',
'<button class="btn-primary" onclick="resetAdvSearch()" style="background:#e74c3c; flex:1;">Réinitialiser</button>',
'<button class="btn-primary" onclick="applyAdvSearch()" style="flex:2;">Appliquer les filtres</button>',
'</div>',
'</div></div>',
# ──────────────────────────────────────────────────────────────────────────────

'</body></html>',
]

html_content = "\n".join(parts)

with open(output_html, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"Fichier HTML genere : {output_html} ({found} elements)")
elapsed = time.time() - start_time
print(f"Page generee en {int(elapsed // 60)} min {int(elapsed % 60)} secondes.")