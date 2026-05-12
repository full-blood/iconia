-- clearListener()
print "install Iconia menu..."

-- Dossiers cibles 3ds Max
local tempDir = GetDir #temp
local userMacroDir = GetDir #userMacros
local startupDir = GetDir #userStartupScripts
local usericonsPath = GetDir #userIcons

-- Exceptions : chemins spéciaux
local iconiaMNXPath = "C:\\Users\\" + sysInfo.username + "\\Autodesk\\3ds Max 2026\\User Settings\\Iconia.mnx"
local iconiaLoaderPath = startupDir + "\\Iconia_loader.ms"

-- Outil de copie système
local System_IO_File = dotNetClass "System.IO.File"

-- 1. Copie explicite des fichiers spéciaux AVANT la boucle générique
if doesFileExist (tempDir + "\\Iconia.mnx") then (
    if doesFileExist iconiaMNXPath then deleteFile iconiaMNXPath
    System_IO_File.Copy (tempDir + "\\Iconia.mnx") iconiaMNXPath
    format "copied Iconia.mnx to %\n" iconiaMNXPath
)

if doesFileExist (tempDir + "\\Iconia_loader.ms") then (
    if doesFileExist iconiaLoaderPath then deleteFile iconiaLoaderPath
    System_IO_File.Copy (tempDir + "\\Iconia_loader.ms") iconiaLoaderPath
    format "copied Iconia_loader.ms to %\n" iconiaLoaderPath
)

-- 2. Boucle générique pour les autres fichiers (.ms, .mcr, .py, .bmp)
for f in getFiles (tempDir + "\\*.*") do (
    local fname = getFilenameFile f   -- nom sans extension
    local ext   = toLower (getFilenameType f)  -- extension avec le point (en minuscules pour la sécurité)

    -- Exclure les fichiers spéciaux déjà traités
    local fullname = fname + ext
    if fullname == "iconia.mnx"         then continue
    if fullname == "iconia_loader.ms"   then continue
    if fullname == "install_scripts.ms" then continue
    if fullname == "mzp.run"            then continue

    -- Destination dynamique selon l'extension
    local dst = undefined

    if (ext == ".ms" or ext == ".mcr" or ext == ".py") then (
        dst = userMacroDir + "\\" + fullname
    ) 
    else if (ext == ".bmp" or ext == ".png" or ext == ".jpg") then (
        -- Si c'est une image/icône, on cible le dossier userIcons
        dst = usericonsPath + "\\" + fullname
    )

    -- Si une destination a été définie, on effectue la copie
    if dst != undefined then (
        if doesFileExist dst then (
            format "remove existing file %...\n" dst
            deleteFile dst
        )
        System_IO_File.Copy f dst
        format "copied % to %\n" f dst
    )
)

print "run the macro, to install it..."