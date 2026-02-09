from io import BytesIO
from unittest.mock import MagicMock

from healthcheck import Handler


class TestHandler:
    def _make_handler(self, method="GET"):
        """Create a Handler with mocked socket."""
        handler = Handler.__new__(Handler)
        handler.requestline = f"{method} / HTTP/1.1"
        handler.request_version = "HTTP/1.1"
        handler.command = method
        handler.headers = {}
        handler.wfile = BytesIO()
        handler.responses = {200: ("OK", "Request fulfilled")}
        handler._headers_buffer = []
        handler.close_connection = True
        return handler

    def test_do_get(self):
        handler = self._make_handler("GET")
        handler.send_response = MagicMock()
        handler.end_headers = MagicMock()
        handler.do_GET()
        handler.send_response.assert_called_once_with(200)
        handler.end_headers.assert_called_once()

    def test_do_head_aliases_get(self):
        assert Handler.do_HEAD is Handler.do_GET

    def test_no_post_handler(self):
        assert not hasattr(Handler, "do_POST")

    def test_no_put_handler(self):
        assert not hasattr(Handler, "do_PUT")

    def test_no_delete_handler(self):
        assert not hasattr(Handler, "do_DELETE")

    def test_no_patch_handler(self):
        assert not hasattr(Handler, "do_PATCH")

    def test_log_message_suppressed(self):
        handler = Handler.__new__(Handler)
        # Should not raise
        handler.log_message("test %s", "arg")
