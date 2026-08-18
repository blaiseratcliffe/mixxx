#include "waveform/renderers/allshader/waveformrendererrgb.h"

#include <cmath>
#include <vector>

#include "track/track.h"
#include "util/math.h"
#include "waveform/renderers/allshader/matrixforwidgetgeometry.h"
#include "waveform/renderers/waveformwidgetrenderer.h"
#include "waveform/waveform.h"

namespace allshader {

namespace {
inline float math_pow2(float x) {
    return x * x;
}
} // namespace

WaveformRendererRGB::WaveformRendererRGB(WaveformWidgetRenderer* waveformWidget,
        ::WaveformRendererAbstract::PositionSource type)
        : WaveformRendererSignalBase(waveformWidget),
          m_isSlipRenderer(type == ::WaveformRendererAbstract::Slip) {
}

void WaveformRendererRGB::onSetup(const QDomNode& node) {
    Q_UNUSED(node);
}

void WaveformRendererRGB::initializeGL() {
    WaveformRendererSignalBase::initializeGL();
    m_shader.init();
}

void WaveformRendererRGB::paintGL() {
    TrackPointer pTrack = m_waveformRenderer->getTrackInfo();
    if (!pTrack || (m_isSlipRenderer && !m_waveformRenderer->isSlipActive())) {
        return;
    }

    auto positionType = m_isSlipRenderer ? ::WaveformRendererAbstract::Slip
                                         : ::WaveformRendererAbstract::Play;

    ConstWaveformPointer waveform = pTrack->getWaveform();
    if (waveform.isNull()) {
        return;
    }

    const int dataSize = waveform->getDataSize();
    if (dataSize <= 1) {
        return;
    }

    const WaveformData* data = waveform->data();
    if (data == nullptr) {
        return;
    }

    const float devicePixelRatio = m_waveformRenderer->getDevicePixelRatio();
    const int length = static_cast<int>(m_waveformRenderer->getLength() * devicePixelRatio);

    // See waveformrenderersimple.cpp for a detailed explanation of the frame and index calculation
    const int visualFramesSize = dataSize / 2;
    const double firstVisualFrame =
            m_waveformRenderer->getFirstDisplayedPosition(positionType) * visualFramesSize;
    const double lastVisualFrame =
            m_waveformRenderer->getLastDisplayedPosition(positionType) * visualFramesSize;

    // Represents the # of visual frames per horizontal pixel.
    const double visualIncrementPerPixel =
            (lastVisualFrame - firstVisualFrame) / static_cast<double>(length);

    // Fixes a sporadic crash caused by a division by zero on waveform initialization
    if (visualIncrementPerPixel == 0.0) {
        return;
    }

    // Per-band gain from the EQ knobs.
    float allGain(1.0), lowGain(1.0), midGain(1.0), highGain(1.0);
    // applyCompensation = false, as we scale to match filtered.all
    getGains(&allGain, false, &lowGain, &midGain, &highGain);

    const float breadth = static_cast<float>(m_waveformRenderer->getBreadth()) * devicePixelRatio;
    const float halfBreadth = breadth / 2.0f;

    // CDJ-style amplitude shaping.
    //
    // The stored Mixxx overall waveform is amplitude-compressed by the
    // analyzer. We undo that below with unscale(), then apply a modest
    // contrast exponent so strong transients stand substantially above
    // the surrounding waveform body.
    // CDJ-style waveform geometry.
    //
    // Global amplitude shaping is deliberately moderate. Local transient
    // contrast is handled in a second pass below.
    constexpr float kAmplitudeExponent = 1.15f;
    constexpr float kAmplitudeGain = 1.85f;
    constexpr float kVerticalFill = 0.98f;

    // Peak-versus-mean emphasis inside each physical screen column.
    constexpr float kPeakAccent = 1.35f;

    // Local peak detector.
    //
    // Each rendered column is compared with neighbouring columns. Sustained
    // high-level sections are reduced while isolated local maxima are boosted.
    constexpr int kNeighborRadius = 4;
    constexpr float kProminenceSensitivity = 3.00f;
    constexpr float kSustainedScale = 0.72f;
    constexpr float kLocalPeakBoost = 1.55f;

    // Keep one full physical pixel. Sub-pixel columns can disappear because
    // the rectangles no longer cover a pixel centre.
    constexpr float kColumnHalfWidth = 0.50f;

    const float low_r = static_cast<float>(m_rgbLowColor_r);
    const float mid_r = static_cast<float>(m_rgbMidColor_r);
    const float high_r = static_cast<float>(m_rgbHighColor_r);
    const float low_g = static_cast<float>(m_rgbLowColor_g);
    const float mid_g = static_cast<float>(m_rgbMidColor_g);
    const float high_g = static_cast<float>(m_rgbHighColor_g);
    const float low_b = static_cast<float>(m_rgbLowColor_b);
    const float mid_b = static_cast<float>(m_rgbMidColor_b);
    const float high_b = static_cast<float>(m_rgbHighColor_b);

    // Effective visual frame for x
    double xVisualFrame = qRound(firstVisualFrame / visualIncrementPerPixel) *
            visualIncrementPerPixel;

    const int numVerticesPerLine = 6; // 2 triangles

    // One waveform rectangle per horizontal pixel plus the centre axis.
    const int reserved = numVerticesPerLine * (length + 1);

    m_vertices.clear();
    m_vertices.reserve(reserved);
    m_colors.clear();
    m_colors.reserve(reserved);

    // First-pass display information.
    //
    // Do not clamp amplitude here. Keeping values above 1 preserves
    // transient differences for the local peak detector.
    std::vector<float> baseAmplitudes(length, 0.f);
    std::vector<float> columnRed(length, 0.f);
    std::vector<float> columnGreen(length, 0.f);
    std::vector<float> columnBlue(length, 0.f);

    m_vertices.addRectangle(0.f,
            halfBreadth - 0.5f * devicePixelRatio,
            static_cast<float>(length),
            m_isSlipRenderer ? halfBreadth : halfBreadth + 0.5f * devicePixelRatio);
    m_colors.addForRectangle(
            static_cast<float>(m_axesColor_r),
            static_cast<float>(m_axesColor_g),
            static_cast<float>(m_axesColor_b));

    const double maxSamplingRange = visualIncrementPerPixel / 2.0;

    for (int pos = 0; pos < length; ++pos) {
        const int visualFrameStart = std::lround(xVisualFrame - maxSamplingRange);
        const int visualFrameStop = std::lround(xVisualFrame + maxSamplingRange);

        const int visualIndexStart = std::max(visualFrameStart * 2, 0);
        const int visualIndexStop =
                std::min(std::max(visualFrameStop, visualFrameStart + 1) * 2, dataSize - 1);

        const float fpos = static_cast<float>(pos);

        // Find the max values for low, mid, high and all in the waveform data.
        // - Max of left and right
        uchar u8maxLow{};
        uchar u8maxMid{};
        uchar u8maxHigh{};
        // - Per channel
        uchar u8maxAllChn[2]{};

        // Also keep the mean unscaled overall amplitude represented by
        // this screen pixel. Comparing peak against mean lets us distinguish
        // short transients from sustained high-level material.
        float meanAllChn[2]{};
        int sampleCountChn[2]{};

        for (int chn = 0; chn < 2; chn++) {
            // data is interleaved left / right
            for (int i = visualIndexStart + chn;
                    i < visualIndexStop + chn;
                    i += 2) {
                const WaveformData& waveformData = data[i];

                u8maxLow =
                        math_max(
                                u8maxLow,
                                waveformData.filtered.low);

                u8maxMid =
                        math_max(
                                u8maxMid,
                                waveformData.filtered.mid);

                u8maxHigh =
                        math_max(
                                u8maxHigh,
                                waveformData.filtered.high);

                u8maxAllChn[chn] =
                        math_max(
                                u8maxAllChn[chn],
                                waveformData.filtered.all);

                meanAllChn[chn] +=
                        unscale(
                                waveformData.filtered.all);

                ++sampleCountChn[chn];
            }

            if (sampleCountChn[chn] > 0) {
                meanAllChn[chn] /=
                        static_cast<float>(
                                sampleCountChn[chn]);
            }
        }

        // Cast to float
        float maxLow = static_cast<float>(u8maxLow);
        float maxMid = static_cast<float>(u8maxMid);
        float maxHigh = static_cast<float>(u8maxHigh);
        // Undo the analyzer's pow(x, 0.632) scaling for the overall
        // amplitude. This restores much more of the original transient
        // dynamic range.
        float maxAllChn[2]{
                unscale(u8maxAllChn[0]),
                unscale(u8maxAllChn[1])};
        // Uncomment to undo scaling with pow(value, 2.0f * 0.316f) done in analyzerwaveform.h
        // float maxAllChn[2]{unscale(u8maxAllChn[0]), unscale(u8maxAllChn[1])};

        // Calculate the squared magnitude of the maxLow, maxMid and maxHigh values.
        // We take the square root to get the magnitude below.
        const float sum = math_pow2(maxLow) + math_pow2(maxMid) + math_pow2(maxHigh);

        // Apply the gains
        maxLow *= lowGain;
        maxMid *= midGain;
        maxHigh *= highGain;

        // Calculate the squared magnitude of the gained maxLow, maxMid and maxHigh values
        // We take the square root to get the magnitude below.
        const float sumGained = math_pow2(maxLow) + math_pow2(maxMid) + math_pow2(maxHigh);

        // The maxAll values will be used to draw the amplitude. We scale them according to
        // magnitude of the gained maxLow, maxMid and maxHigh values
        if (sum != 0.f) {
            // magnitude = sqrt(sum) and magnitudeGained = sqrt(sumGained), and
            // factor = magnitudeGained / magnitude, but we can do with a single sqrt:
            const float factor = std::sqrt(sumGained / sum);
            maxAllChn[0] *= factor;
            maxAllChn[1] *= factor;
        }

        // CDJ-style 3Band colour weighting.
        //
        // Normalize the bands against each other, NOT against 255.
        // This makes hue depend on the spectral ratio rather than the
        // absolute loudness of the waveform column.
        const float bandMax =
                math_max3(maxLow, maxMid, maxHigh);

        float red = 0.f;
        float green = 0.f;
        float blue = 0.f;

        if (bandMax > 0.f) {
            const float lowNormalized = maxLow / bandMax;
            const float midNormalized = maxMid / bandMax;
            const float highNormalized = maxHigh / bandMax;

            // Contrast exponent = 2.0.
            // x*x is substantially cheaper than std::pow() in this hot loop.
            const float lowWeight =
                    lowNormalized * lowNormalized;
            const float midWeight =
                    midNormalized * midNormalized;
            const float highWeight =
                    highNormalized * highNormalized;

            const float weightSum =
                    lowWeight + midWeight + highWeight;

            if (weightSum > 0.f) {
                red = (lowWeight * low_r +
                              midWeight * mid_r +
                              highWeight * high_r) /
                        weightSum;

                green = (lowWeight * low_g +
                                midWeight * mid_g +
                                highWeight * high_g) /
                        weightSum;

                blue = (lowWeight * low_b +
                               midWeight * mid_b +
                               highWeight * high_b) /
                        weightSum;

                // Make the dominant colour component vivid while preserving
                // the band ratio.
                const float maxComponent =
                        math_max3(red, green, blue);

                if (maxComponent > 0.f) {
                    const float normFactor =
                            1.f / maxComponent;

                    red *= normFactor;
                    green *= normFactor;
                    blue *= normFactor;
                }
            }
        }

        // CDJ-style amplitude geometry.
        //
        // maxAllChn has already been unscaled back toward the original
        // amplitude. Use the stronger channel as a mirrored envelope.
        const float peakAmplitude =
                math_max(
                        maxAllChn[0],
                        maxAllChn[1]);

        const float meanAmplitude =
                math_max(
                        meanAllChn[0],
                        meanAllChn[1]);

        // A transient has a peak substantially above the mean represented
        // by this pixel. Accent that difference while leaving sustained
        // sections much closer to their normal envelope.
        const float accentedAmplitude =
                meanAmplitude +
                kPeakAccent *
                        math_max(
                                0.f,
                                peakAmplitude -
                                        meanAmplitude);

        const float rawAmplitude =
                math_max(
                        0.f,
                        allGain *
                                accentedAmplitude /
                                m_maxValue);

        const float contrastedAmplitude =
                std::pow(
                        rawAmplitude,
                        kAmplitudeExponent);

        // IMPORTANT:
        // Do not clamp here. Values above 1 contain useful information about
        // which transient is actually stronger. Clamping before local peak
        // detection would turn strong neighbouring columns into a plateau.
        baseAmplitudes[pos] =
                contrastedAmplitude *
                kAmplitudeGain;

        columnRed[pos] = red;
        columnGreen[pos] = green;
        columnBlue[pos] = blue;

        xVisualFrame += visualIncrementPerPixel;
    }

    // ---------------------------------------------------------
    // Second pass: local transient prominence shaping
    // ---------------------------------------------------------
    //
    // The original Mixxx renderer treats every horizontal pixel independently,
    // which makes loud sustained regions form broad rectangular plateaus.
    //
    // Here we compare each column with a small neighbourhood:
    //
    //   sustained region:
    //       current ~= neighbours -> reduce toward kSustainedScale
    //
    //   transient:
    //       current > neighbours  -> preserve / boost toward kLocalPeakBoost
    //
    // This produces taller, narrower visually distinct peaks without changing
    // the underlying waveform analysis.
    for (int pos = 0; pos < length; ++pos) {
        const float current =
                baseAmplitudes[pos];

        float neighborSum = 0.f;
        int neighborCount = 0;

        for (int offset = -kNeighborRadius;
                offset <= kNeighborRadius;
                ++offset) {
            if (offset == 0) {
                continue;
            }

            const int neighborPos =
                    pos + offset;

            if (neighborPos < 0 ||
                    neighborPos >= length) {
                continue;
            }

            neighborSum +=
                    baseAmplitudes[neighborPos];

            ++neighborCount;
        }

        const float neighborMean =
                neighborCount > 0
                ? neighborSum /
                        static_cast<float>(
                                neighborCount)
                : current;

        // Relative rise of the current column above its local surroundings.
        //
        // A sustained block gives approximately zero.
        // A sharp kick / transient gives a positive value.
        const float denominator =
                math_max(
                        current,
                        0.000001f);

        const float relativeRise =
                math_max(
                        0.f,
                        (current -
                                neighborMean) /
                                denominator);

        const float prominence =
                math_clamp(
                        relativeRise *
                                kProminenceSensitivity,
                        0.f,
                        1.f);

        // Suppress broad sustained material.
        //
        // prominence = 0:
        //      scale = kSustainedScale
        //
        // prominence = 1:
        //      scale = 1
        const float bodyScale =
                kSustainedScale +
                (1.f -
                        kSustainedScale) *
                        prominence;

        // Then selectively enlarge true local peaks.
        //
        // prominence = 0:
        //      boost = 1
        //
        // prominence = 1:
        //      boost = kLocalPeakBoost
        const float transientBoost =
                1.f +
                (kLocalPeakBoost -
                        1.f) *
                        prominence;

        // Final clamp happens only now, after local peak comparison.
        const float displayAmplitude =
                math_clamp(
                        current *
                                bodyScale *
                                transientBoost,
                        0.f,
                        1.f);

        const float displayHeight =
                halfBreadth *
                kVerticalFill *
                displayAmplitude;

        const float fpos =
                static_cast<float>(
                        pos);

        m_vertices.addRectangle(
                fpos - kColumnHalfWidth,
                halfBreadth - displayHeight,
                fpos + kColumnHalfWidth,
                m_isSlipRenderer
                        ? halfBreadth
                        : halfBreadth +
                                displayHeight);

        m_colors.addForRectangle(
                columnRed[pos],
                columnGreen[pos],
                columnBlue[pos]);
    }

    DEBUG_ASSERT(reserved == m_vertices.size());
    DEBUG_ASSERT(reserved == m_colors.size());

    const QMatrix4x4 matrix = matrixForWidgetGeometry(m_waveformRenderer, true);

    const int matrixLocation = m_shader.matrixLocation();
    const int positionLocation = m_shader.positionLocation();
    const int colorLocation = m_shader.colorLocation();

    m_shader.bind();
    m_shader.enableAttributeArray(positionLocation);
    m_shader.enableAttributeArray(colorLocation);

    m_shader.setUniformValue(matrixLocation, matrix);

    m_shader.setAttributeArray(
            positionLocation, GL_FLOAT, m_vertices.constData(), 2);
    m_shader.setAttributeArray(
            colorLocation, GL_FLOAT, m_colors.constData(), 3);

    glDrawArrays(GL_TRIANGLES, 0, m_vertices.size());

    m_shader.disableAttributeArray(positionLocation);
    m_shader.disableAttributeArray(colorLocation);
    m_shader.release();
}

} // namespace allshader
