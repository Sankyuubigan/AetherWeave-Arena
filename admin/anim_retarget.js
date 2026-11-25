// Ретаргет Mixamo-FBX клипа на скелет скина-GLB для браузерного превью (вьюер «Анимации»).
//
// Зачем: навесить FBX-клип на аватар «как есть» НЕЛЬЗЯ — rest-позы ригов разные.
// У аватара (Blender-экспорт скина) armature повёрнута на −90°X и сжата в 0.01,
// Hips имеет свою локальную позицию в другом фрейме ([-1.83, -118.7] против [0, 99.8]),
// а локальные rest-повороты части костей различаются (Hips — 90°, плечи — 0.48 рад,
// большие пальцы — 0.29 рад). Сырые FBX-кватернионы дают вместо фигуры «комок» ~0.9 м.
//
// Тот же принцип, что в Godot-пайплайне `Generators/bake_anim_glb.py` (там переносятся
// МАТРИЦЫ костей по именам, т.к. rest-позы различаются):
//   поворот: q_аватара = rest_local_аватара * (rest_local_fbx^-1 * q_fbx)
//   позиция корневой кости: мировая дельта FBX → локальный фрейм аватара.
// Позиции остальных костей отбрасываются (в Mixamo-ригах они константны, кроме Hips).

import * as THREE from 'three';

const NON_ALNUM = /[^A-Za-z0-9_]/g;

/** Ключ кости: снимаем неймспейс `mixamorig1:` (часть FBX) и любую пунктуацию. */
export function boneKey(name) {
  return String(name).replace(/^mixamorig1/, 'mixamorig').replace(NON_ALNUM, '');
}

/** Rest-локальные трансформы костей рига → Map[key] = {q, p}. Снимать ТОЛЬКО в покое. */
export function captureRest(root) {
  const m = new Map();
  root.traverse(o => {
    if (o.isBone) m.set(boneKey(o.name), { q: o.quaternion.clone(), p: o.position.clone() });
  });
  return m;
}

function rootBone(root) {
  let found = null;
  root.traverse(o => { if (!found && o.isBone && !(o.parent && o.parent.isBone)) found = o; });
  return found;
}

// Матрица без трансляции: превращает вектор-разницу в согласованных единицах.
function dirMatrix(m) {
  const c = m.clone();
  c.elements[12] = c.elements[13] = c.elements[14] = 0;
  return c;
}

/**
 * Собрать клип, который корректно играется на скелете аватара.
 * @param {THREE.AnimationClip} clip   исходный клип (FBX)
 * @param {THREE.Object3D} srcRoot     корень FBX-рига (в покое, до проигрывания)
 * @param {THREE.Object3D} avatarRoot  корень аватара
 * @param {Map} avatarRest             captureRest(avatarRoot), снятый в покое
 * @returns {THREE.AnimationClip|null}
 */
export function buildAvatarClip(clip, srcRoot, avatarRoot, avatarRest) {
  if (!clip || !avatarRest) return null;
  const srcRest = captureRest(srcRoot);
  const avBones = new Map();
  avatarRoot.traverse(o => { if (o.isBone) avBones.set(boneKey(o.name), o); });

  const avHips = rootBone(avatarRoot);
  const srcHips = rootBone(srcRoot);
  const hipsKey = avHips ? boneKey(avHips.name) : null;

  avatarRoot.updateMatrixWorld(true);
  srcRoot.updateMatrixWorld(true);
  const mSrc = srcHips && srcHips.parent ? dirMatrix(srcHips.parent.matrixWorld) : new THREE.Matrix4();
  const mAvInv = avHips && avHips.parent
    ? dirMatrix(new THREE.Matrix4().copy(avHips.parent.matrixWorld).invert())
    : new THREE.Matrix4();
  const restWorldSrc = new THREE.Vector3();
  if (srcHips) restWorldSrc.copy(srcRest.get(hipsKey).p).applyMatrix4(mSrc);
  const restWorldAv = new THREE.Vector3();
  if (avHips) restWorldAv.copy(avatarRest.get(hipsKey).p)
    .applyMatrix4(avHips.parent ? avHips.parent.matrixWorld : new THREE.Matrix4());
  // Единицы ригов РАЗНЫЕ: Mixamo-FBX загружается в сантиметрах (Hips в мире = 99.79),
  // аватар-GLB — в метрах (Hips = 1.187). Смещение корня переносим в пропорции ростов
  // ригов — так же нормируют ретаргетеры Mixamo (иначе корень уезжает в −6 м).
  const unit = restWorldSrc.lengthSq() > 1e-8 ? restWorldAv.length() / restWorldSrc.length() : 0.01;

  const tracks = [];
  const q = new THREE.Quaternion();
  const v = new THREE.Vector3();

  for (const t of clip.tracks) {
    const m = /^(.+?)\.(quaternion|position|scale)$/.exec(String(t.name));
    if (!m) continue;
    const key = boneKey(m[1]);
    const prop = m[2];
    const av = avBones.get(key);
    const restA = avatarRest.get(key);
    const restS = srcRest.get(key);
    if (!av || !restA || !restS) continue;           // кости нет в одном из ригов — трек лишний

    if (prop === 'quaternion') {
      const pre = restA.q.clone().multiply(restS.q.clone().invert());
      const vals = new Float32Array(t.values.length);
      for (let i = 0; i < t.values.length; i += 4) {
        q.fromArray(t.values, i).premultiply(pre);
        vals[i] = q.x; vals[i + 1] = q.y; vals[i + 2] = q.z; vals[i + 3] = q.w;
      }
      tracks.push(new THREE.QuaternionKeyframeTrack(av.name + '.quaternion', t.times.slice(), vals));
    } else if (prop === 'position' && key === hipsKey && srcHips) {
      const vals = new Float32Array(t.values.length);
      for (let i = 0; i < t.values.length; i += 3) {
        v.fromArray(t.values, i).applyMatrix4(mSrc).sub(restWorldSrc).multiplyScalar(unit);
        // Превью «in place»: горизонтальный root-motion (бег/лазание уводят персонажа за
        // кадр) не переносим, вертикаль (прыжок/присед) сохраняем.
        v.x = 0; v.z = 0;
        v.applyMatrix4(mAvInv);
        const out = restA.p.clone().add(v);
        vals[i] = out.x; vals[i + 1] = out.y; vals[i + 2] = out.z;
      }
      tracks.push(new THREE.VectorKeyframeTrack(av.name + '.position', t.times.slice(), vals));
    }
    // scale и позиции не-корневых костей не переносим: в Mixamo-ригах они константны
  }
  if (!tracks.length) return null;
  return new THREE.AnimationClip(clip.name, clip.duration, tracks);
}
