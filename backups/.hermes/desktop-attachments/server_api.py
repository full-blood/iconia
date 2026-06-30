from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import subprocess
import threading
import uuid
import shlex
import json
from pathlib import Path
from typing import List
import sqlite3

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SCRIPTS_DIR   = Path(r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\scripts")
SECRET_TOKEN  = "RENDER_TEAM_2024"
MODELS_ROOT   = Path(r"\\CGLibrary\CgLibrary\3-Models")
TASK_NAME     = "Regen_3DModels_Library"
SCRIPT_PATH   = r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\scripts\Models_checked_update.py"
CONFIG_PATH   = Path(r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\config.json")
BACKUP_LOG    = Path(r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\backup.log")
BACKUP_SCRIPT = Path(r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\scripts\backup_models.py")
DATABASE_PATH = Path(r"\\CGLibrary\CgLibrary\0-Documentation\3DS Max Configuration\3DS Max Plugins\Antoine\API\library.db")

jobs: dict[str, str] = {}


# ── Models ────────────────────────────────────────────────────────────────────

class ScriptRequest(BaseModel):
    token: str
    args: str = ""

class TokenOnly(BaseModel):
    token: str

class ToggleTaskRequest(BaseModel):
    token: str
    time: str = "08:00"

class SetTimeRequest(BaseModel):
    token: str
    time: str

class ScheduleUpdateRequest(BaseModel):
    token:             str
    enabled:           bool
    interval_minutes:  int = 90

class TxtReadRequest(BaseModel):
    token: str
    path: str

class TxtWriteRequest(BaseModel):
    token: str
    path: str
    content: str

class UpdateAssetRequest(BaseModel):
    token:       str
    name:        str
    category:    str = ""
    subcategory: str = ""
    keywords:    List[str] = []

class UserRequest(BaseModel):
    username: str
    new_username: str = ""

class FavoriteToggleRequest(BaseModel):
    username: str
    model_name: str
    
class RenameCategoryRequest(BaseModel):
    token: str
    old_category: str
    old_subcategory: str = ""
    new_category: str
    new_subcategory: str = ""

# ── Helpers ───────────────────────────────────────────────────────────────────

def check_token(token: str):
    if token != SECRET_TOKEN:
        raise HTTPException(status_code=401, detail="Token invalide")

def check_path_safe(path_str: str) -> Path:
    p = Path(path_str).resolve()
    try:
        p.relative_to(MODELS_ROOT.resolve())
    except ValueError:
        raise HTTPException(status_code=403, detail="Chemin non autorise")
    if not p.name.endswith("_CHECKED_OK.txt"):
        raise HTTPException(status_code=403, detail="Seuls les fichiers _CHECKED_OK.txt sont modifiables")
    return p

def run_script_and_track(cmd: list, cwd: str, job_id: str):
    jobs[job_id] = "running"
    try:
        result = subprocess.run(cmd, cwd=cwd)
        jobs[job_id] = "done" if result.returncode == 0 else "error"
    except Exception:
        jobs[job_id] = "error"

def schtasks(*args) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["schtasks", *args],
        capture_output=True, text=True, encoding="cp850"
    )

# ── Routes principales ────────────────────────────────────────────────────────

@app.get("/")
def read_root():
    return {"status": "Online", "server": "RENDER-01"}

@app.post("/run/{script_name}")
def run_script(script_name: str, payload: ScriptRequest):
    check_token(payload.token)
    script_path = SCRIPTS_DIR / script_name
    if not script_path.exists():
        raise HTTPException(status_code=404, detail=f"Script '{script_name}' introuvable")
    cmd = ["python", str(script_path)]
    if payload.args:
        cmd.extend(shlex.split(payload.args))
    job_id = str(uuid.uuid4())
    t = threading.Thread(target=run_script_and_track, args=(cmd, str(SCRIPTS_DIR), job_id), daemon=True)
    t.start()
    return {"status": "Success", "message": f"Script {script_name} lance", "job_id": job_id}

@app.get("/job-status/{job_id}")
def job_status(job_id: str):
    return {"job_id": job_id, "status": jobs.get(job_id, "unknown")}

@app.post("/read-txt")
def read_txt(payload: TxtReadRequest):
    check_token(payload.token)
    p = check_path_safe(payload.path)
    if not p.exists():
        raise HTTPException(status_code=404, detail="Fichier introuvable")
    try:
        return {"status": "ok", "content": p.read_text(encoding="utf-8-sig")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/write-txt")
def write_txt(payload: TxtWriteRequest):
    check_token(payload.token)
    p = check_path_safe(payload.path)
    if not p.exists():
        raise HTTPException(status_code=404, detail="Fichier introuvable")
    try:
        p.write_text(payload.content, encoding="utf-8")
        return {"status": "ok", "message": f"Fichier mis a jour : {p.name}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Task Scheduler ────────────────────────────────────────────────────────────

@app.get("/task/status")
def task_status():
    r = schtasks("/query", "/tn", TASK_NAME, "/fo", "LIST")
    if r.returncode != 0:
        return {"exists": False, "enabled": False, "time": None}
    enabled = True
    time    = None
    for line in r.stdout.splitlines():
        line = line.strip()
        if "sactiv" in line or "isabled" in line:
            enabled = False
        if "cution" in line.lower():
            parts = line.split(":", 1)
            if len(parts) == 2:
                tokens = parts[1].strip().split()
                if len(tokens) >= 2:
                    time = tokens[1][:5]
    return {"exists": True, "enabled": enabled, "time": time}

@app.post("/task/toggle")
def task_toggle(payload: ToggleTaskRequest):
    check_token(payload.token)
    status = task_status()
    if not status["exists"]:
        raise HTTPException(status_code=404, detail="Tache introuvable")
    if status["enabled"]:
        r = schtasks("/change", "/tn", TASK_NAME, "/disable")
        if r.returncode != 0:
            raise HTTPException(status_code=500, detail=r.stderr + " | " + r.stdout)
        return {"status": "ok", "action": "desactivee", "enabled": False}
    else:
        r = schtasks("/change", "/tn", TASK_NAME, "/enable")
        if r.returncode != 0:
            raise HTTPException(status_code=500, detail=r.stderr + " | " + r.stdout)
        return {"status": "ok", "action": "activee", "enabled": True}

@app.post("/task/set-time")
def task_set_time(payload: SetTimeRequest):
    check_token(payload.token)
    parts = payload.time.split(":")
    if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
        raise HTTPException(status_code=400, detail="Format invalide HH:MM")
    r = schtasks("/change", "/tn", TASK_NAME, "/st", payload.time)
    if r.returncode != 0:
        raise HTTPException(status_code=500, detail=r.stderr + " | " + r.stdout)
    return {"status": "ok", "time": payload.time}

@app.get("/task/debug")
def task_debug():
    r = schtasks("/query", "/tn", TASK_NAME, "/fo", "LIST")
    return {"stdout": r.stdout, "stderr": r.stderr, "returncode": r.returncode}


# ── Scheduler Python (config.json) ───────────────────────────────────────────

@app.post("/schedule/update")
def schedule_update(payload: ScheduleUpdateRequest):
    check_token(payload.token)
    interval = max(1, payload.interval_minutes)
    config = {"enabled": payload.enabled, "interval_minutes": interval}
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return {"status": "ok", "enabled": payload.enabled, "interval_minutes": interval}

@app.get("/schedule/status")
def schedule_status():
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        # Compatibilité ancienne config avec "time"
        if "interval_minutes" not in data:
            data["interval_minutes"] = 90
        return data
    except Exception:
        return {"enabled": False, "interval_minutes": 90}


# ── Library JSON ──────────────────────────────────────────────────────────────

# ── Informations de la Bibliothèque ───────────────────────────────────────────

@app.get("/library/info")
def library_info():
    """Retourne les métadonnées + fichiers manquants depuis SQLite."""
    if not DATABASE_PATH.exists():
        return {"status": "not_found", "generated": None, "count": 0, "missing": []}
    
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # 1. Récupération des métadonnées
        cursor.execute("SELECT key, value FROM Metadata")
        meta_rows = cursor.fetchall()
        metadata = {row["key"]: row["value"] for row in meta_rows}

        # 2. Récupération des fichiers manquants
        cursor.execute("SELECT name, missing_type AS missing, folder_path AS path FROM MissingFiles")
        missing_rows = [dict(row) for row in cursor.fetchall()]
        
        conn.close()

        return {
            "status":    "ok",
            "generated": metadata.get("generated_at"),
            "count":     int(metadata.get("count", 0)),
            "missing":   missing_rows
        }
    except Exception as e:
        # Si la table n'existe pas encore, on renvoie un état vide
        return {"status": "not_found", "generated": None, "count": 0, "missing": []}

@app.post("/library/update-asset")
def library_update_asset(payload: UpdateAssetRequest):
    """Met à jour un seul asset directement dans SQLite (instantané)."""
    check_token(payload.token)
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()

        # Vérifier si le modèle existe
        cursor.execute("SELECT id FROM Models WHERE name = ?", (payload.name,))
        if not cursor.fetchone():
            conn.close()
            return {"status": "not_found", "message": f"Asset '{payload.name}' non trouve dans SQLite"}

        # Mise à jour des données
        keywords_str = ",".join(payload.keywords)
        cat = payload.category or ".None"
        subcat = payload.subcategory or "none"

        cursor.execute('''
            UPDATE Models
            SET category = ?, subcategory = ?, keywords = ?
            WHERE name = ?
        ''', (cat, subcat, keywords_str, payload.name))

        conn.commit()
        conn.close()
        
        return {"status": "ok", "name": payload.name}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Backup ────────────────────────────────────────────────────────────────────

@app.post("/backup/start")
def backup_start(payload: TokenOnly):
    check_token(payload.token)
    if not BACKUP_SCRIPT.exists():
        raise HTTPException(status_code=404, detail="Script backup_models.py introuvable")
    job_id = str(uuid.uuid4())
    t = threading.Thread(
        target=run_script_and_track,
        args=(["python", str(BACKUP_SCRIPT)], str(SCRIPTS_DIR), job_id),
        daemon=True
    )
    t.start()
    return {"status": "Success", "job_id": job_id}

@app.get("/backup/status")
def backup_status():
    robocopy_log = BACKUP_LOG.parent / "robocopy.log"
    try:
        if not robocopy_log.exists():
            return {"last_backup": None, "status": "never"}
        mtime = robocopy_log.stat().st_mtime
        from datetime import datetime
        last_date = datetime.fromtimestamp(mtime).strftime("%d.%m.%Y %H:%M")
        return {"last_backup": last_date, "status": "ok"}
    except Exception as e:
        return {"last_backup": None, "status": "error", "detail": str(e)}


# ── Base de données SQLite ────────────────────────────────────────────────────
@app.get("/api/models")
def get_all_models():
    """Récupère tous les modèles depuis la base de données SQLite."""
    if not DATABASE_PATH.exists():
        return {"status": "error", "message": "Base de données introuvable. Veuillez lancer une régénération."}
    
    try:
        # Connexion à la BDD
        conn = sqlite3.connect(DATABASE_PATH)
        # row_factory permet de récupérer les données sous forme de dictionnaire (avec les noms de colonnes)
        conn.row_factory = sqlite3.Row 
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM Models ORDER BY category, subcategory, name")
        rows = cursor.fetchall()
        conn.close()
        
        # Conversion en liste de dictionnaires
        models_list = [dict(row) for row in rows]
        
        return {"status": "Success", "count": len(models_list), "data": models_list}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Gestion des Utilisateurs et Favoris ───────────────────────────────────────

@app.get("/api/users")
def get_users():
    """Liste tous les utilisateurs."""
    if not DATABASE_PATH.exists():
        return []
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT username FROM Users ORDER BY username ASC")
    users = [row[0] for row in cursor.fetchall()]
    conn.close()
    return users

@app.post("/api/users/create")
def create_user(payload: UserRequest):
    """Crée un nouvel utilisateur."""
    if not payload.username.strip():
        raise HTTPException(status_code=400, detail="Nom d'utilisateur vide")
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO Users (username) VALUES (?)", (payload.username.strip(),))
        conn.commit()
        return {"status": "ok", "message": "Utilisateur cree"}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Cet utilisateur existe deja")
    finally:
        conn.close()

@app.post("/api/users/delete")
def delete_user(payload: UserRequest):
    """Supprime un utilisateur et ses favoris."""
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM Users WHERE username = ?", (payload.username,))
    user = cursor.fetchone()
    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="Utilisateur introuvable")
    
    cursor.execute("DELETE FROM Favorites WHERE user_id = ?", (user[0],))
    cursor.execute("DELETE FROM Users WHERE id = ?", (user[0],))
    conn.commit()
    conn.close()
    return {"status": "ok"}

@app.post("/api/users/rename")
def rename_user(payload: UserRequest):
    """Renomme un utilisateur."""
    if not payload.new_username.strip():
        raise HTTPException(status_code=400, detail="Nouveau nom vide")
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE Users SET username = ? WHERE username = ?", (payload.new_username.strip(), payload.username))
        conn.commit()
        return {"status": "ok"}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Ce nom est deja utilise")
    finally:
        conn.close()

@app.get("/api/favorites/{username}")
def get_user_favorites(username: str):
    """Récupère la liste des noms de modèles mis en favoris par l'utilisateur."""
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT f.model_name FROM Favorites f
        JOIN Users u ON f.user_id = u.id
        WHERE u.username = ?
    ''', (username,))
    favs = [row[0] for row in cursor.fetchall()]
    conn.close()
    return favs

@app.post("/api/favorites/toggle")
def toggle_favorite(payload: FavoriteToggleRequest):
    """Ajoute ou supprime un modèle des favoris d'un utilisateur."""
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    cursor.execute("SELECT id FROM Users WHERE username = ?", (payload.username,))
    user = cursor.fetchone()
    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="Utilisateur introuvable")
    
    user_id = user[0]
    cursor.execute("SELECT 1 FROM Favorites WHERE user_id = ? AND model_name = ?", (user_id, payload.model_name))
    exists = cursor.fetchone()
    
    if exists:
        cursor.execute("DELETE FROM Favorites WHERE user_id = ? AND model_name = ?", (user_id, payload.model_name))
        action = "removed"
    else:
        cursor.execute("INSERT INTO Favorites (user_id, model_name) VALUES (?, ?)", (user_id, payload.model_name))
        action = "added"
        
    conn.commit()
    conn.close()
    return {"status": "ok", "action": action}
    
@app.get("/api/categories")
def get_categories():
    """Récupère l'arborescence dynamique des catégories et sous-catégories."""
    if not DATABASE_PATH.exists():
        return {}
    
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    # On récupère toutes les combinaisons uniques existantes
    cursor.execute("SELECT DISTINCT category, subcategory FROM Models WHERE category IS NOT NULL")
    rows = cursor.fetchall()
    conn.close()

    categories_dict = {}
    for cat, subcat in rows:
        if not cat: continue
        if cat not in categories_dict:
            categories_dict[cat] = set()
        if subcat and subcat.lower() != "none":
            categories_dict[cat].add(subcat)

    # On convertit les sets en listes triées pour le JSON
    return {k: sorted(list(v), key=lambda x: x.lower()) for k, v in categories_dict.items()}
    
@app.post("/api/categories/rename")
def rename_category(payload: RenameCategoryRequest):
    """Renomme une catégorie ET/OU une sous-catégorie dans la BDD et les .txt."""
    check_token(payload.token)
    old_cat = payload.old_category.strip()
    old_sub = payload.old_subcategory.strip()
    new_cat = payload.new_category.strip()
    new_sub = payload.new_subcategory.strip()

    if not old_cat or not new_cat:
        raise HTTPException(status_code=400, detail="Le nom de la categorie principale est obligatoire")

    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()

    # 1. Sélection des fichiers cibles
    if old_sub:
        cursor.execute("SELECT txt_path FROM Models WHERE category = ? AND subcategory = ?", (old_cat, old_sub))
    else:
        cursor.execute("SELECT txt_path FROM Models WHERE category = ?", (old_cat,))
    
    rows = cursor.fetchall()
    updated_files = 0

    for row in rows:
        txt_path = Path(row[0])
        if txt_path.exists():
            try:
                content = txt_path.read_text(encoding="utf-8-sig")
                lines = content.splitlines()
                new_lines = []
                
                for line in lines:
                    stripped = line.strip()
                    if not old_sub: 
                        # Mode 1 : Renommage de la catégorie principale uniquement
                        if stripped.startswith("-") and not stripped.startswith("--") and stripped[1:].strip().lower() == old_cat.lower():
                            new_lines.append(f"- {new_cat}")
                        else:
                            new_lines.append(line)
                    else:
                        # Mode 2 : Renommage ciblé d'une sous-catégorie
                        if stripped.startswith("-") and not stripped.startswith("--") and stripped[1:].strip().lower() == old_cat.lower():
                            new_lines.append(f"- {new_cat}") # Mise à jour de la catégorie parente
                        elif stripped.startswith("--") and stripped[2:].strip().lower() == old_sub.lower():
                            if new_sub and new_sub.lower() != "none":
                                new_lines.append(f"-- {new_sub}")
                            # Si new_sub est vide, on l'ignore (ça supprime la sous-catégorie)
                        else:
                            new_lines.append(line)
                
                txt_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
                updated_files += 1
            except Exception as e:
                print(f"Erreur d'écriture sur {txt_path}: {e}")

    # 2. Mise à jour de la base de données
    if old_sub:
        cursor.execute("UPDATE Models SET category = ?, subcategory = ? WHERE category = ? AND subcategory = ?", (new_cat, new_sub or "none", old_cat, old_sub))
    else:
        cursor.execute("UPDATE Models SET category = ? WHERE category = ?", (new_cat, old_cat))
        
    conn.commit()
    conn.close()

    return {"status": "ok", "message": f"{updated_files} fichiers TXT mis a jour"}
    
@app.get("/api/keywords")
def get_all_keywords():
    """Récupère une liste unique de tous les mots-clés utilisés."""
    if not DATABASE_PATH.exists():
        return []
    
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT keywords FROM Models WHERE keywords IS NOT NULL AND keywords != ''")
    rows = cursor.fetchall()
    conn.close()

    unique_kws = set()
    for row in rows:
        # Les mots clés sont stockés sous forme "mot1,mot2,mot3"
        for kw in row[0].split(','):
            cleaned = kw.strip()
            if cleaned:
                unique_kws.add(cleaned)

    # On retourne la liste triée alphabétiquement
    return sorted(list(unique_kws), key=lambda x: x.lower())