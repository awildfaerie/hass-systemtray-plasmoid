#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantMap>

class BackupFileReader : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    Q_INVOKABLE QVariantMap readFile(const QUrl &url) const;
};
