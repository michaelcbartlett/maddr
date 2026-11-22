## Open a Godot character

Double-click `E:\repos\mad villain\Open PixelStudio.bat`. It starts the local Godot helper, opens PixelStudio, and loads the basic cop's walk as an editable puppet. The editor's **Open Godot character** button also connects to the running helper when `index.html` is opened directly.

The dialog reads `enemies/enemy_painter.gd` in the connected project. **Choose .gd…** lets you select that source file explicitly. Choose **Basic cop** and **Walk**, **Idle**, or **Baton attack**, then **Open editable puppet**. Unsupported scripts and files from another project produce an explanation rather than opening as flattened art.

Each clip has 18 named layers: torso, head, hair, face, hat, upper arms, forearms, hands, thighs, shins, feet, and baton. All parts retain their hidden pixels; the original poses reconstruct the game's artwork exactly. Joints are placed for each frame and parent links are already set up. Select **Edit arm** and press **T** to rotate around the shoulder; its forearm, hand and baton follow. **Edit baton** rotates just the baton around its grip. **P** adjusts a pivot, **V** moves a part, and **Edit range** controls which frames change. Leave **Children follow their parent** enabled for puppet posing.

The weapon anchor follows the baton layer's grip and direction, including when a parent moves. **Save project** retains parts, poses, parent links, source information and weapon directions. **Load project** restores these without needing the helper. The imported frames use lighting generated from the current artwork so a moved limb does not leave a stale fixed normal map behind; they do not preserve the game's original physical height profiles. Parts carry the original silhouette outline; large pose changes may need small outline repairs at newly exposed joints.

The helper only listens on `127.0.0.1:8766`. It requires Python and Godot (`GODOT_PATH` or `~/Tools/Godot`). It runs the adapter in an isolated temporary project and does not modify the game's drawing scripts or saves. Generated projects are also saved in `E:\repos\mad villain\export\pixelstudio\cop-walk` (and `cop-idle`, `cop-attack`). Editing or saving a PixelStudio project does not replace game art automatically.

To stop the helper, close its Python process or stop the local bridge from your process manager. Logs are in `E:\repos\mad villain\.local\pixelstudio-bridge*.log`. For a visible terminal session, run `python tools/pixelstudio/bridge.py --open` from the Mad Villain folder.
