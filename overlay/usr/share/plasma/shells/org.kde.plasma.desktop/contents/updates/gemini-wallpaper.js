// Gemini PDA: make "Gemini 01" (/usr/share/wallpapers/Gemini01, from the
// repo's Wallpapers/gemini_01.png) the desktop wallpaper.
// plasmashell runs each update script once per user, after the desktop is
// loaded (new users too) and records it in ~/.config/plasmashellrc
// [Updates] performed — so a wallpaper the user picks later stays.
desktops().forEach(function (d) {
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/Gemini01/");
    d.reloadConfig();
});
