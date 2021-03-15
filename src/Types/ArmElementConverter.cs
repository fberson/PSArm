
// Copyright (c) Microsoft Corporation.

using PSArm.Templates.Primitives;
using System;
using System.Collections;
using System.Management.Automation;

namespace PSArm.Types
{
    public class ArmElementConverter : PSTypeConverter
    {
        public override bool CanConvertFrom(object sourceValue, Type destinationType)
        {
            if (sourceValue is null)
            {
                return true;
            }

            Type sourceType = sourceValue.GetType();
            switch (Type.GetTypeCode(sourceType))
            {
                case TypeCode.Object:
                    return typeof(IEnumerable).IsAssignableFrom(destinationType)
                        || typeof(IDictionary).IsAssignableFrom(destinationType);

                default:
                    return true;
            }
        }

        public override bool CanConvertTo(object sourceValue, Type destinationType)
        {
            return false;
        }

        public override object ConvertFrom(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            if (!ArmElementConversion.TryConvertToArmElement(sourceValue, out ArmElement armElement))
            {
                throw new InvalidCastException($"Value of type '{sourceValue.GetType()}' could not be converted to type '{destinationType}'");
            }

            return armElement;
        }

        public override object ConvertTo(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            throw new NotImplementedException();
        }
    }

    public class ArmExpressionConverter : PSTypeConverter
    {
        public override bool CanConvertFrom(object sourceValue, Type destinationType)
        {
            if (sourceValue is null)
            {
                return true;
            }

            if (Type.GetTypeCode(sourceValue.GetType()) != TypeCode.Object)
            {
                return true;
            }

            return sourceValue is ArmExpression;
        }

        public override bool CanConvertTo(object sourceValue, Type destinationType)
        {
            return false;
        }

        public override object ConvertFrom(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            if (!ArmElementConversion.TryConvertToArmExpression(sourceValue, out ArmExpression armExpression))
            {
                throw new InvalidCastException($"Value of type '{sourceValue.GetType()}' could not be converted to type '{destinationType}'");
            }

            return armExpression;
        }

        public override object ConvertTo(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            throw new NotImplementedException();
        }
    }
}