#include "waveform/widgets/allshader/cdjwaveformwidget.h"

#include "waveform/renderers/allshader/waveformrenderbackground.h"
#include "waveform/renderers/allshader/waveformrenderbeat.h"
#include "waveform/renderers/allshader/waveformrendererendoftrack.h"
#include "waveform/renderers/allshader/waveformrendererpreroll.h"
#include "waveform/renderers/allshader/waveformrenderercdj.h"
#include "waveform/renderers/allshader/waveformrendererslipmode.h"
#include "waveform/renderers/allshader/waveformrendermark.h"
#include "waveform/renderers/allshader/waveformrendermarkrange.h"
#include "waveform/widgets/allshader/moc_cdjwaveformwidget.cpp"

namespace allshader {

CDJWaveformWidget::CDJWaveformWidget(const QString& group, QWidget* parent)
        : WaveformWidget(group, parent) {
    addRenderer<WaveformRenderBackground>();
    addRenderer<WaveformRendererEndOfTrack>();
    addRenderer<WaveformRendererPreroll>();
    addRenderer<WaveformRenderMarkRange>();
    addRenderer<WaveformRendererCDJ>();
    addRenderer<WaveformRenderBeat>();
    addRenderer<WaveformRenderMark>();
    // The following renderer will add an overlay waveform if a slip is in progress
    addRenderer<WaveformRendererSlipMode>();
    addRenderer<WaveformRendererPreroll>(::WaveformRendererAbstract::Slip);
    addRenderer<WaveformRendererCDJ>(::WaveformRendererAbstract::Slip);
    addRenderer<WaveformRenderBeat>(::WaveformRendererAbstract::Slip);
    addRenderer<WaveformRenderMark>(::WaveformRendererAbstract::Slip);

    m_initSuccess = init();
}

void CDJWaveformWidget::castToQWidget() {
    m_widget = this;
}

void CDJWaveformWidget::paintEvent(QPaintEvent* event) {
    Q_UNUSED(event);
}

} // namespace allshader
