# Editable doctor melee

Double-click **Open Doctor Melee.bat** in the Mad Villain repository root.
This opens Video to Frames / Pixel & Motion Studio with the dual-sword doctor loaded.
The **Open Godot character** dialog also offers primary sword, primary knife, dual swords and dual knives.

The doctor body is a paintable layer. Each active melee arm has separate upper-arm, forearm,
hand and weapon layers. Weapons are parented to their hands, with the rotation pivot at the grip.
The hand draws over the handle, just as in the edited cop baton.

- Click **Primary blade** or **Secondary blade**, then press **T** to rotate just that weapon at the fist.
- **Primary arm** / **Secondary arm** rotate the whole arm with its forearm, hand and weapon following.
- Select the forearm or hand in Layers to adjust the elbow or wrist separately.
- **V** moves a part; **P** changes its pivot. Keep **Children follow their parent** enabled.
- **Save project** preserves the editable layers, joints, poses and weapon anchor.

These `.pixelstudio` files are the editable source projects. Saving one does not automatically replace
the game's procedural drawing; preserve the layered project when passing back the edited pose.
