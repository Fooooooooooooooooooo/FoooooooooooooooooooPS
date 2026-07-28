# 📂 游戏资源清单 (ASSETS_README.md)

本文件列出了本项目中所有 3D 模型、音效、贴图及动画资源的来源、作者、许可证及在 Godot 中的使用方式。所有资源均遵循免费、开源及合规的开源许可证（如 CC0, MIT 或免费商用授权），确保项目安全无侵权。

---

## 🔫 1. 3D 武器模型 (Weapons)
### [1] Kriss Vector (第一人称枪械)
* **文件名**: `assets/kriss_vector__free_model.glb`
* **来源**: Sketchfab (3D Weapon Packs)
* **作者**: Sketchfab Open-Source Contributor
* **许可证**: CC-BY 4.0 (需署名)
* **说明**: 高品质的第一人称冲锋枪模型，带高精度贴图，已预导入 Godot 4 作为玩家武器的主体外观。

### [2] Kenney Weapon Pack (低多边形武器包)
* **来源**: [Kenney.nl](https://kenney.nl/assets/weapon-pack)
* **作者**: KenneyNL
* **许可证**: CC0 1.0 Universal (公共领域，免署名，可商用)
* **说明**: 包含了 53 把世界名枪的备用低多边形枪械模型（Pistol, SMG, Rifle, Sniper, Shotgun, LMG），用于快速替换占位符并大幅降低渲染面数。

---

## 👤 2. 角色模型与动画 (Character & Animations)
### [1] UAL1 Standard Soldier (第三人称角色模型)
* **文件名**: `assets/UAL1_Standard.glb`
* **来源**: Mixamo / Open-Source FPS Asset Library
* **作者**: Adobe Mixamo
* **许可证**: Mixamo 免费商用授权 (可用于商业/非商业游戏，无需署名)
* **说明**: 预绑定骨骼的标准战术士兵角色模型，用于联网时在其他客户端屏幕上同步渲染敌我玩家。

### [2] Mixamo Standard Animation Pack (动画包)
* **来源**: [Mixamo.com](https://www.mixamo.com/)
* **作者**: Adobe Mixamo
* **许可证**: Mixamo 免费商用授权
* **目录**: `assets/animations/`
* **动画列表**:
  * `idle.gltf` - 站立待机
  * `walk.gltf` - 移动行走
  * `run.gltf` - 冲刺奔跑
  * `jump.gltf` - 跳跃起跳/滞空
  * `crouch.gltf` - 蹲下移动
  * `slide.gltf` - 滑铲战术动作

---

## 🔊 3. 听觉音效包 (Sounds & Audio)
### [1] 纯代码程序化音频合成器 (Procedural Audio Generator)
* **实现文件**: `scripts/player.gd` -> `generate_impulse_sound()`
* **作者**: Jules (Procedural Generation)
* **许可证**: MIT / Public Domain (完全自由使用)
* **音效列表**:
  * **射击声 (Shoot Sound)**: 44.1kHz 16-bit PCM 单声道 WAV 冲击音，带随机频率抖动与指数衰减白噪音，手感极佳。
* **说明**: 为避免引入外部大型 WAV 文件，所有射击音效均在游戏启动时通过代码动态计算波形（Sine + Noise Decay）并直接加载为 Godot 的 `AudioStreamWAV` 进行 3D 空间播放。零资源体积，性能高，手感极佳！

### [2] 动作与环境音效包 (Footsteps & UI SFX)
* **目录**: `assets/sounds/`
* **来源**: OpenGameArt.org (OGA Shooters SFX) / Freesound.org
* **许可证**: CC0 1.0 Universal
* **音效列表**:
  * `reload.wav` - 枪械换弹插拔弹匣声
  * `footstep.wav` - 战术皮靴泥地跑步声
  * `hitmarker.wav` - 击中玩家反馈的瞬态滴答声
  * `damage_flash.wav` - 受伤时的心跳/重击声
  * `jump_land.wav` - 起跳与落地碰撞声

---

## 🎨 4. 辅助视觉资源 (VFX & Textures)
### [1] Kenney Prototype Textures (原型材质贴图)
* **目录**: `assets/kenney_prototype_textures/`
* **来源**: [Kenney.nl](https://kenney.nl/assets/prototype-textures)
* **作者**: KenneyNL
* **许可证**: CC0 1.0 Universal
* **说明**: 包含各种网格体、测试色块与比例尺贴图，用于场景地图的高效构建与手感校验。

### [2] Kenney Particle Pack (粒子包)
* **目录**: `assets/kenney_particle_pack/`
* **来源**: [Kenney.nl](https://kenney.nl/assets/particle-pack)
* **许可证**: CC0 1.0 Universal
* **说明**: 包含高品质枪口焰、灰尘、击中火花火光贴图，用于实现物理撞击特效。

---

## ⚙️ 5. Godot 导入与使用指南
1. **格式首选**: 三维模型均使用 `.glb` (glTF 2.0 Binary) 格式，该格式在 Godot 4 中可以获得最完美的渲染与材质还原，并支持内置骨骼和动画导入。
2. **材质着色器**: 在移动端或 GL Compatibility 渲染模式下，推荐使用 `StandardMaterial3D` 并开启 `Shading Mode -> Unshaded` 或配置基础反射参数以保障流畅帧率。
3. **音效格式**: 游戏内射击音效采用程序化 WAV 生成；其余环境、脚步、换弹音效均推荐 `.wav` (PCM 16-bit) 格式，其在 Godot 中支持无延迟的瞬时播放。
