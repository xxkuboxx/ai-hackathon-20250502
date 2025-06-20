# logging_config.py

import logging
import sys
import os
import json # JSONフォーマッタ用
from typing import Optional

from google.cloud.logging.handlers import CloudLoggingHandler, setup_logging # CloudLoggingHandlerは直接API用なので注意
from asgi_correlation_id import correlation_id

from config import settings

old_factory = logging.getLogRecordFactory()

def record_factory(*args, **kwargs):
    record = old_factory(*args, **kwargs)
    record.correlation_id = correlation_id.get()
    record.service_name = "sessionmuse-backend"
    return record

logging.setLogRecordFactory(record_factory)

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord):
        log_entry = {
            "timestamp": self.formatTime(record, self.datefmt),
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "correlation_id": getattr(record, 'correlation_id', None),
            "service_name": getattr(record, 'service_name', None),
            "logging.googleapis.com/labels": {
                "correlation_id": getattr(record, 'correlation_id', None),
            } if getattr(record, 'correlation_id', None) else {},
            "logging.googleapis.com/sourceLocation": {
                "file": record.pathname,
                "line": record.lineno,
                "function": record.funcName,
            } if record.pathname else {},
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        if record.stack_info:
            log_entry["stack_trace"] = self.formatStack(record.stack_info)
        
        standard_attrs = set(logging.LogRecord('', '', '', '', '', '', '', '').__dict__.keys())
        standard_attrs.update(['correlation_id', 'service_name', 'message', 'asctime'])
        extra_attrs = {k: v for k, v in record.__dict__.items() if k not in standard_attrs}
        if extra_attrs:
            log_entry["extra_data"] = extra_attrs
            
        return json.dumps(log_entry, default=str)

def setup_app_logging(log_level_str: str = settings.LOG_LEVEL):
    level = getattr(logging, log_level_str.upper(), logging.INFO)
    logging.getLogger().setLevel(level)

    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    running_in_gcp = bool(os.environ.get("GOOGLE_CLOUD_PROJECT"))

    if running_in_gcp:
        json_handler = logging.StreamHandler(sys.stdout)
        formatter = JsonFormatter()
        json_handler.setFormatter(formatter)
        json_handler.setLevel(level)
        logging.getLogger().addHandler(json_handler)
        logging.info(f"GCP環境用にJSONロギングを設定しました。ログレベル: {log_level_str}")
    else:
        console_handler = logging.StreamHandler(sys.stdout)
        formatter_str = "%(asctime)s - %(levelname)s - %(name)s:%(funcName)s:%(lineno)d - RID:%(correlation_id)s - %(message)s"
        if level <= logging.DEBUG:
             formatter_str = "%(asctime)s - %(levelname)s - %(name)s:%(funcName)s:%(lineno)d - RID:%(correlation_id)s - %(pathname)s - %(module)s - %(message)s"
        formatter = logging.Formatter(formatter_str)
        console_handler.setFormatter(formatter)
        console_handler.setLevel(level)
        logging.getLogger().addHandler(console_handler)
        logging.info(f"ローカル環境用にコンソールロギングを設定しました。ログレベル: {log_level_str}")

    logging.getLogger("uvicorn.access").setLevel(logging.WARNING if level > logging.INFO else logging.INFO)
    logging.getLogger("uvicorn.error").setLevel(level)
    logging.getLogger("fastapi").setLevel(level)
    logging.getLogger("watchfiles").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.INFO if level > logging.DEBUG else logging.DEBUG)
    logging.getLogger("google").setLevel(logging.INFO)
