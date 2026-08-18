#pragma once

#include "shaders/rgbshader.h"
#include "util/class.h"
#include "waveform/renderers/allshader/rgbdata.h"
#include "waveform/renderers/allshader/vertexdata.h"
#include "waveform/renderers/allshader/waveformrenderersignalbase.h"

namespace allshader {
class WaveformRendererCDJ;
}

class allshader::WaveformRendererCDJ final : public allshader::WaveformRendererSignalBase {
  public:
    explicit WaveformRendererCDJ(WaveformWidgetRenderer* waveformWidget,
            ::WaveformRendererAbstract::PositionSource type =
                    ::WaveformRendererAbstract::Play);

    // override ::WaveformRendererSignalBase
    void onSetup(const QDomNode& node) override;

    void initializeGL() override;
    void paintGL() override;

  private:
    mixxx::RGBShader m_shader;
    VertexData m_vertices;
    RGBData m_colors;

    bool m_isSlipRenderer;

    DISALLOW_COPY_AND_ASSIGN(WaveformRendererCDJ);
};
