#include "backupfilereader.h"

#include <QFile>

QVariantMap BackupFileReader::readFile(const QUrl &url) const
{
    if (!url.isLocalFile()) {
        return {
            {QStringLiteral("error"), QStringLiteral("The selected backup is not a local file.")},
        };
    }

    QFile file(url.toLocalFile());
    if (!file.open(QIODevice::ReadOnly)) {
        return {
            {QStringLiteral("error"), file.errorString()},
        };
    }

    constexpr qint64 maxBackupSize = 1024 * 1024;
    const QByteArray contents = file.read(maxBackupSize + 1);
    if (file.error() != QFileDevice::NoError) {
        return {
            {QStringLiteral("error"), file.errorString()},
        };
    }
    if (contents.size() > maxBackupSize) {
        return {
            {QStringLiteral("error"), QStringLiteral("The selected backup file is too large.")},
        };
    }

    return {
        {QStringLiteral("contents"), QString::fromUtf8(contents)},
    };
}
