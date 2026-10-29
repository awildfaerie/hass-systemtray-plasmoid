#include "backupfilereader.h"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class BackupReaderPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<BackupFileReader>(uri, 1, 0, "BackupFileReader");
    }
};

#include "backupreaderplugin.moc"
