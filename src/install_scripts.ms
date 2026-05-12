-- clearListener()
print "install Iconia menu..."

-- Temp folder et user macros
tempDir = GetDir #temp
userMacroDir = GetDir #userMacros

-- Exceptions : chemins spéciaux
iconiaMNXPath = "C:\\Users\\" + sysInfo.username + "\\Autodesk\\3ds Max 2026\\User Settings\\Iconia.mnx"
iconiaLoaderPath = "C:\\Users\\" + sysInfo.username + "\\AppData\\Local\\Autodesk\\3dsMax\\2026 - 64bit\\ENU\\scripts\\startup\\Iconia_loader.ms"

-- Copie explicite des fichiers spéciaux AVANT la boucle générique
if doesFileExist (tempDir + "\\Iconia.mnx") then (
    if doesFileExist iconiaMNXPath then deleteFile iconiaMNXPath
    (dotNetClass "System.IO.File").Copy (tempDir + "\\Iconia.mnx") iconiaMNXPath
    format "copied Iconia.mnx to %\n" iconiaMNXPath
)

if doesFileExist (tempDir + "\\Iconia_loader.ms") then (
    if doesFileExist iconiaLoaderPath then deleteFile iconiaLoaderPath
    (dotNetClass "System.IO.File").Copy (tempDir + "\\Iconia_loader.ms") iconiaLoaderPath
    format "copied Iconia_loader.ms to %\n" iconiaLoaderPath
)

-- Boucle générique pour les autres fichiers (.ms, .mcr, .py) vers userMacros
for f in getFiles (tempDir + "\\*.*") do (
    local fname = getFilenameFile f   -- nom sans extension
    local ext   = getFilenameType f   -- extension avec le point

    -- Exclure les fichiers spéciaux déjà traités
    local fullname = fname + ext
    if fullname == "Iconia.mnx"      then continue
    if fullname == "Iconia_loader.ms" then continue
    if fullname == "install_scripts.ms" then continue
    if fullname == "mzp.run"            then continue

    if (ext == ".ms" or ext == ".mcr" or ext == ".py") then (
        local dst = userMacroDir + "\\" + fullname
        if doesFileExist dst then (
            format "remove existing file %...\n" dst
            deleteFile dst
        )
        (dotNetClass "System.IO.File").Copy f dst
        format "copied % to %\n" f dst
    )
)

print "run the macro, to install it..."