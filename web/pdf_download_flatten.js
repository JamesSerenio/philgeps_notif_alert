import * as pdfjsLib from 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.10.38/pdf.min.mjs';
import { PDFDocument } from 'https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/+esm';

pdfjsLib.GlobalWorkerOptions.workerSrc =
  'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.10.38/pdf.worker.min.mjs';

window.pdfjsLib = pdfjsLib;

window.flattenFinalBidPdf = async (editedBytes) => {
  const renderScale = 300 / 72;

  // Copy the exact bytes received from Flutter.
  const inputBytes = new Uint8Array(editedBytes);

  console.log(
    'FLATTENER INPUT:',
    inputBytes.length,
    inputBytes[0],
    inputBytes[1],
    inputBytes[2],
    inputBytes[3],
  );

  const source = await pdfjsLib.getDocument({
    data: inputBytes,
    disableFontFace: false,
    useSystemFonts: true,
  }).promise;

  const output = await PDFDocument.create();

  try {
    for (
      let pageNumber = 1;
      pageNumber <= source.numPages;
      pageNumber += 1
    ) {
      const sourcePage = await source.getPage(pageNumber);

      const pageSize = sourcePage.getViewport({
        scale: 1,
      });

      const renderSize = sourcePage.getViewport({
        scale: renderScale,
      });

      const canvas = document.createElement('canvas');

      canvas.width = Math.ceil(renderSize.width);
      canvas.height = Math.ceil(renderSize.height);

      const context = canvas.getContext('2d', {
        alpha: false,
        willReadFrequently: false,
      });

      if (!context) {
        throw new Error(
          `Unable to create canvas context for page ${pageNumber}.`,
        );
      }

      context.save();

      context.fillStyle = '#ffffff';
      context.fillRect(
        0,
        0,
        canvas.width,
        canvas.height,
      );

    await sourcePage.render({
      canvasContext: context,
      viewport: renderSize,
      intent: 'display',
      background: '#ffffff',
      annotationMode: pdfjsLib.AnnotationMode.ENABLE,
    }).promise;

      context.restore();

      // ======================================================
      // DEBUG PAGE 1
      // ======================================================

      if (pageNumber === 1) {
        console.log(
          'PDF.js PAGE 1 rendered:',
          canvas.width,
          canvas.height,
        );

        // Keep this temporarily.
        // This lets us verify exactly what PDF.js rasterized.
        const debugUrl = canvas.toDataURL(
          'image/png',
          1.0,
        );

        console.log(
          'PDF.js PAGE 1 PNG READY',
          debugUrl.substring(0, 80),
        );
      }

      // ======================================================
      // PNG
      // ======================================================

      const pngBlob = await new Promise(
        (resolve, reject) => {
          canvas.toBlob(
            (blob) => {
              if (blob) {
                resolve(blob);
              } else {
                reject(
                  new Error(
                    `Unable to encode PDF page ${pageNumber}.`,
                  ),
                );
              }
            },
            'image/png',
            1.0,
          );
        },
      );

      const pngBytes =
        new Uint8Array(
          await pngBlob.arrayBuffer(),
        );

      const image =
        await output.embedPng(pngBytes);

      // ======================================================
      // NEW PDF PAGE
      // ======================================================

      const outputPage = output.addPage([
        pageSize.width,
        pageSize.height,
      ]);

      outputPage.drawImage(image, {
        x: 0,
        y: 0,
        width: pageSize.width,
        height: pageSize.height,
      });

      // Free browser memory.
      canvas.width = 1;
      canvas.height = 1;

      sourcePage.cleanup();
    }

    // ========================================================
    // SAVE IMAGE-ONLY PDF
    // ========================================================

    const imageOnlyBytes =
      await output.save({
        useObjectStreams: true,
      });

    // ========================================================
    // VERIFY NO TEXT EXISTS
    // ========================================================

    const verification =
      await pdfjsLib.getDocument({
        data: imageOnlyBytes.slice(0),
      }).promise;

    try {
      if (
        verification.numPages !==
        source.numPages
      ) {
        throw new Error(
          `Final PDF page count mismatch. ` +
          `Source=${source.numPages}, ` +
          `Final=${verification.numPages}`,
        );
      }

      for (
        let pageNumber = 1;
        pageNumber <= verification.numPages;
        pageNumber += 1
      ) {
        const page =
          await verification.getPage(
            pageNumber,
          );

        const textContent =
          await page.getTextContent();

        if (textContent.items.length !== 0) {
          throw new Error(
            `Final PDF verification failed: ` +
            `page ${pageNumber} still contains ` +
            `${textContent.items.length} text objects.`,
          );
        }

        page.cleanup();
      }
    } finally {
      await verification.destroy();
    }

    console.log(
      'FINAL IMAGE PDF:',
      imageOnlyBytes.length,
      'bytes',
    );

    return imageOnlyBytes;
  } finally {
    await source.destroy();
  }
};