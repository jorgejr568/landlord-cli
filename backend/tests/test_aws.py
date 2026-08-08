from __future__ import annotations

import re
from unittest.mock import MagicMock, patch

import pytest

import rentivo.aws as aws_module
from rentivo.aws import build_client


class TestBuildClientKwargs:
    @patch("rentivo.aws.boto3")
    def test_passes_service_region_and_credentials(self, mock_boto3):
        mock_boto3.client.return_value = MagicMock()

        client = build_client(
            "s3",
            region="us-east-1",
            access_key_id="key",
            secret_access_key="secret",
            feature="S3 storage",
        )

        assert client is mock_boto3.client.return_value
        mock_boto3.client.assert_called_once_with(
            service_name="s3",
            region_name="us-east-1",
            aws_access_key_id="key",
            aws_secret_access_key="secret",
        )

    @patch("rentivo.aws.boto3")
    def test_forwards_endpoint_url_when_provided(self, mock_boto3):
        mock_boto3.client.return_value = MagicMock()

        build_client(
            "kms",
            region="us-east-1",
            access_key_id="key",
            secret_access_key="secret",
            endpoint_url="http://localstack:4566",
            feature="KMS encryption",
        )

        call_kwargs = mock_boto3.client.call_args.kwargs
        assert call_kwargs["service_name"] == "kms"
        assert call_kwargs["endpoint_url"] == "http://localstack:4566"

    @patch("rentivo.aws.boto3")
    def test_omits_endpoint_url_when_empty(self, mock_boto3):
        mock_boto3.client.return_value = MagicMock()

        build_client(
            "ses",
            region="us-east-1",
            access_key_id="key",
            secret_access_key="secret",
            endpoint_url="",
            feature="SES email",
        )

        assert "endpoint_url" not in mock_boto3.client.call_args.kwargs


class TestBuildClientMissingBoto3:
    def test_raises_with_feature_specific_message(self):
        expected = "boto3 is required for S3 storage. Install it with: pip install rentivo[s3]"

        with patch.object(aws_module, "boto3", None):
            with pytest.raises(ImportError, match=re.escape(expected)) as excinfo:
                build_client(
                    "s3",
                    region="r",
                    access_key_id="k",
                    secret_access_key="s",
                    feature="S3 storage",
                )

        assert str(excinfo.value) == expected

    def test_appends_note_to_the_message_when_given(self):
        note = "(the s3 extras group also provides the boto3 client used for KMS)."
        expected = (
            "boto3 is required for KMS encryption. Install it with: pip install rentivo[s3] "
            "(the s3 extras group also provides the boto3 client used for KMS)."
        )

        with patch.object(aws_module, "boto3", None):
            with pytest.raises(ImportError) as excinfo:
                build_client(
                    "kms",
                    region="r",
                    access_key_id="k",
                    secret_access_key="s",
                    feature="KMS encryption",
                    note=note,
                )

        assert str(excinfo.value) == expected

    def test_does_not_build_a_client_when_boto3_is_absent(self):
        with patch.object(aws_module, "boto3", None):
            with pytest.raises(ImportError):
                build_client(
                    "ses",
                    region="r",
                    access_key_id="k",
                    secret_access_key="s",
                    endpoint_url="http://localstack:4566",
                    feature="SES email",
                )
