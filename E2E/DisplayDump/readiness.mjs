function rectangleDescription(rectangle) {
  if (!rectangle) return "missing";
  return `${rectangle.x},${rectangle.y} ${rectangle.width}x${rectangle.height}`;
}

function usableRectangle(rectangle) {
  return ["x", "y", "width", "height"].every((key) =>
    Number.isFinite(Number(rectangle?.[key])),
  ) && Number(rectangle.width) >= 1_024 && Number(rectangle.height) >= 768;
}

function rectanglesOverlap(left, right) {
  return left.x < right.x + right.width
    && left.x + left.width > right.x
    && left.y < right.y + right.height
    && left.y + left.height > right.y;
}

export function displayReadinessMismatches(actual, manifest) {
  const mismatches = [];
  const displays = Array.isArray(actual?.displays) ? actual.displays : [];
  const expectedAppKit = manifest?.guest?.displays?.appKit ?? [];

  if (actual?.screenCaptureAllowed !== true) {
    mismatches.push("screen capture is not authorized");
  }
  if (displays.length !== expectedAppKit.length) {
    mismatches.push(
      `display count is ${displays.length}; expected ${expectedAppKit.length}`,
    );
  }

  const mainDisplays = displays.filter(({isMain}) => isMain === true);
  if (mainDisplays.length !== 1) {
    mismatches.push(`main display count is ${mainDisplays.length}; expected 1`);
  }

  for (let index = 0; index < displays.length; index += 1) {
    const alias = `D${index + 1}`;
    const display = displays[index];
    if (!usableRectangle(display.frame)) {
      mismatches.push(
        `${alias} AppKit frame is not usable: ${rectangleDescription(display.frame)}`,
      );
    }
    if (!usableRectangle(display.coreGraphicsBounds)) {
      mismatches.push(
        `${alias} Core Graphics bounds are not usable: ${rectangleDescription(display.coreGraphicsBounds)}`,
      );
    }
  }

  for (let left = 0; left < displays.length; left += 1) {
    for (let right = left + 1; right < displays.length; right += 1) {
      const leftBounds = displays[left].coreGraphicsBounds;
      const rightBounds = displays[right].coreGraphicsBounds;
      if (
        usableRectangle(leftBounds)
        && usableRectangle(rightBounds)
        && rectanglesOverlap(leftBounds, rightBounds)
      ) {
        mismatches.push(`D${left + 1} and D${right + 1} overlap`);
      }
    }
  }

  return mismatches;
}
