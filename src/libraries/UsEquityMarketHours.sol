// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title UsEquityMarketHours
/// @notice Utilities for checking US equity market hours (09:30-16:00 ET, Mon-Fri) with DST support.
library UsEquityMarketHours {
    uint256 internal constant SECONDS_PER_DAY = 1 days;
    uint256 internal constant MARKET_OPEN = 9 hours + 30 minutes;
    uint256 internal constant MARKET_CLOSE = 16 hours;
    uint256 internal constant UTC_OFFSET_EST = 5 hours;
    uint256 internal constant UTC_OFFSET_EDT = 4 hours;
    int256 internal constant OFFSET19700101 = 2_440_588;

    /// @notice Returns true if timestamp is within US equity market hours.
    /// @dev Uses America/New_York DST rules (second Sunday in March, first Sunday in November).
    function isWithinUsEquityHours(uint256 timestamp) internal pure returns (bool) {
        bool isDst = _isDst(timestamp);
        int256 offset = isDst ? -int256(UTC_OFFSET_EDT) : -int256(UTC_OFFSET_EST);
        int256 localTs = int256(timestamp) + offset;
        if (localTs < 0) return false;

        uint256 local = uint256(localTs);
        uint256 dayOfWeek = _dayOfWeek(local);
        if (dayOfWeek == 0 || dayOfWeek == 6) return false; // Sunday or Saturday

        uint256 secondsInDay = local % SECONDS_PER_DAY;
        return secondsInDay >= MARKET_OPEN && secondsInDay <= MARKET_CLOSE;
    }

    function _isDst(uint256 timestamp) private pure returns (bool) {
        uint256 year = _getYear(timestamp);
        uint256 dstStart = _dstStartUtc(year);
        uint256 dstEnd = _dstEndUtc(year);
        return timestamp >= dstStart && timestamp < dstEnd;
    }

    function _dstStartUtc(uint256 year) private pure returns (uint256) {
        // Second Sunday in March at 02:00 local time (EST) = 07:00 UTC.
        uint256 marchFirstDow = _dayOfWeekFromDate(year, 3, 1); // 0=Sunday
        uint256 firstSunday = marchFirstDow == 0 ? 1 : 8 - marchFirstDow;
        uint256 secondSunday = firstSunday + 7;
        return _timestampFromDateTime(year, 3, secondSunday, 7, 0, 0);
    }

    function _dstEndUtc(uint256 year) private pure returns (uint256) {
        // First Sunday in November at 02:00 local time (EDT) = 06:00 UTC.
        uint256 novFirstDow = _dayOfWeekFromDate(year, 11, 1); // 0=Sunday
        uint256 firstSunday = novFirstDow == 0 ? 1 : 8 - novFirstDow;
        return _timestampFromDateTime(year, 11, firstSunday, 6, 0, 0);
    }

    function _getYear(uint256 timestamp) private pure returns (uint256 year) {
        (year,,) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    function _dayOfWeek(uint256 timestamp) private pure returns (uint256) {
        uint256 daysSinceEpoch = timestamp / SECONDS_PER_DAY;
        return (daysSinceEpoch + 4) % 7; // 1970-01-01 was a Thursday (4 if Sunday=0)
    }

    function _dayOfWeekFromDate(uint256 year, uint256 month, uint256 day) private pure returns (uint256) {
        uint256 daysSinceEpoch = _daysFromDate(year, month, day);
        return (daysSinceEpoch + 4) % 7;
    }

    function _timestampFromDateTime(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 second
    )
        private
        pure
        returns (uint256)
    {
        uint256 daysSinceEpoch = _daysFromDate(year, month, day);
        return daysSinceEpoch * SECONDS_PER_DAY + hour * 1 hours + minute * 1 minutes + second;
    }

    function _daysFromDate(uint256 year, uint256 month, uint256 day) private pure returns (uint256 _days) {
        int256 _year = int256(year);
        int256 _month = int256(month);
        int256 _day = int256(day);

        int256 _daysInt = _day - 32_075 + 1461 * (_year + 4800 + (_month - 14) / 12) / 4 + 367
            * (_month - 2 - (_month - 14) / 12 * 12) / 12 - 3 * ((_year + 4900 + (_month - 14) / 12) / 100) / 4
            - OFFSET19700101;

        _days = uint256(_daysInt);
    }

    function _daysToDate(uint256 _days) private pure returns (uint256 year, uint256 month, uint256 day) {
        int256 _daysInt = int256(_days);

        int256 l = _daysInt + 68_569 + OFFSET19700101;
        int256 n = 4 * l / 146_097;
        l = l - (146_097 * n + 3) / 4;
        int256 _year = 4000 * (l + 1) / 1_461_001;
        l = l - 1461 * _year / 4 + 31;
        int256 _month = 80 * l / 2447;
        int256 _day = l - 2447 * _month / 80;
        l = _month / 11;
        _month = _month + 2 - 12 * l;
        _year = 100 * (n - 49) + _year + l;

        year = uint256(_year);
        month = uint256(_month);
        day = uint256(_day);
    }
}
