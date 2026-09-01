function sameRectangle(actual, expected) {
  return ["x", "y", "width", "height"].every(
    (key) => Number(actual?.[key]) === Number(expected?.[key]),
  );
}

function rectangleDescription(rectangle) {
  if (!rectangle) return "missing";
  return `${rectangle.x},${rectangle.y} ${rectangle.width}x${rectangle.height}`;
}

export function displayReadinessMismatches(actual, manifest) {
  const mismatches = [];
  const displays = Array.isArray(actual?.displays) ? actual.displays : [];
  const expectedAppKit = manifest?.guest?.displays?.appKit ?? [];
  const expectedCoreGraphics = manifest?.guest?.displays?.coreGraphics ?? [];

  if (actual?.screenCaptureAllowed !== true) {
    mismatches.push("screen capture is not authorized");
  }
  if (displays.length !== expectedAppKit.length) {
    mismatches.push(
      `display count is ${displays.length}; expected ${expectedAppKit.length}`,
    );
  }

  for (let index = 0; index < expectedAppKit.length; index += 1) {
    const alias = expectedAppKit[index].name;
    const display = displays[index];
    if (!display) {
      mismatches.push(`${alias} is missing`);
      continue;
    }

    const expectedMain = index === 0;
    if (display.isMain !== expectedMain) {
      mismatches.push(`${alias} main=${display.isMain}; expected ${expectedMain}`);
    }
    if (!sameRectangle(display.frame, expectedAppKit[index])) {
      mismatches.push(
        `${alias} AppKit frame is ${rectangleDescription(display.frame)}; expected ${rectangleDescription(expectedAppKit[index])}`,
      );
    }
    if (!sameRectangle(display.coreGraphicsBounds, expectedCoreGraphics[index])) {
      mismatches.push(
        `${alias} Core Graphics bounds are ${rectangleDescription(display.coreGraphicsBounds)}; expected ${rectangleDescription(expectedCoreGraphics[index])}`,
      );
    }
  }

  return mismatches;
}
